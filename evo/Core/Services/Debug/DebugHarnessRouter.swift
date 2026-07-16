#if DEBUG
    import AppKit
    import Foundation
    import os
    import SwiftData

    enum DebugHarnessRouter {
        enum HarnessError: Error {
            case timeout
        }

        /// Structured concurrency (`withThrowingTaskGroup`) cannot return until every child task
        /// completes, even after `cancelAll()` — cancellation is only a cooperative flag. An
        /// operation suspended inside `withCheckedContinuation` awaiting a non-cancellation-aware
        /// callback (e.g. WKWebView's `evaluateJavaScript`) never observes that flag, so a task
        /// group racing it against a timeout does not bound wall-clock time. Use a single
        /// continuation instead: whichever of {operation, timer} finishes first resumes it, guarded
        /// by a lock so only the first winner's result is delivered. If the operation hangs, its
        /// `Task` keeps running in the background and its eventual result/error is silently dropped
        /// via the `resumed` guard once the timeout has already resumed the continuation — this is
        /// intended, documented behavior, not a leak of the timeout guarantee.
        static func harnessTimeout<T: Sendable>(
            seconds: Double,
            _ operation: @escaping @Sendable () async throws -> T
        ) async throws -> T {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                Task {
                    do {
                        let value = try await operation()
                        let first = resumed.withLock { alreadyResumed -> Bool in
                            if alreadyResumed {
                                return false
                            }
                            alreadyResumed = true
                            return true
                        }
                        if first {
                            continuation.resume(returning: value)
                        }
                    } catch {
                        let first = resumed.withLock { alreadyResumed -> Bool in
                            if alreadyResumed {
                                return false
                            }
                            alreadyResumed = true
                            return true
                        }
                        if first {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    let first = resumed.withLock { alreadyResumed -> Bool in
                        if alreadyResumed {
                            return false
                        }
                        alreadyResumed = true
                        return true
                    }
                    if first {
                        continuation.resume(throwing: HarnessError.timeout)
                    }
                }
            }
        }

        /// WebKit hands back NSString/NSNumber/NSArray/NSDictionary/NSNull. Anything else is stringified.
        static func jsonSafe(_ value: Any?) -> Any {
            guard let value else { return NSNull() }
            if JSONSerialization.isValidJSONObject(["v": value]) {
                return value
            }
            return String(describing: value)
        }

        static func writePNG(image: NSImage, to path: String) -> HarnessHTTPResponse {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                return HarnessHTTPResponse.error("png encode failed", status: 500)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                return HarnessHTTPResponse.json([
                    "path": path,
                    "width": Int(rep.pixelsWide),
                    "height": Int(rep.pixelsHigh)
                ])
            } catch {
                return HarnessHTTPResponse.error("write failed: \(error.localizedDescription)", status: 500)
            }
        }

        /// `TabManager.containers` is a `@Query` declared on a plain `ObservableObject`, not a `View`,
        /// so SwiftUI never binds it to a live `ModelContext` and it always reads as empty outside the
        /// normal view-update cycle. Fetch containers directly from the manager's `modelContext` instead
        /// (mirrors `TabManager.fetchContainers()`, which is `private`).
        @MainActor
        private static func liveContainers(for tabManager: TabManager) -> [TabContainer] {
            let descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)])
            return (try? tabManager.modelContext.fetch(descriptor)) ?? []
        }

        @MainActor
        static func route(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return HarnessHTTPResponse.json([
                    "ok": true,
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    "pid": Int(ProcessInfo.processInfo.processIdentifier)
                ])

            case ("GET", "/windows"):
                let windows = DebugHarnessRegistry.shared.snapshots().map { snapshot -> [String: Any] in
                    let tabCount = liveContainers(for: snapshot.tabManager).reduce(0) { $0 + $1.tabs.count }
                    return [
                        "windowID": snapshot.id.uuidString,
                        "isPrivate": snapshot.isPrivate,
                        "tabCount": tabCount
                    ]
                }
                return HarnessHTTPResponse.json(windows)

            case ("GET", "/tabs"):
                var snapshots = DebugHarnessRegistry.shared.snapshots()
                if let windowRaw = request.query["window"] {
                    guard let windowID = UUID(uuidString: windowRaw) else {
                        return HarnessHTTPResponse.error("bad window id", status: 400)
                    }
                    snapshots = snapshots.filter { $0.id == windowID }
                }
                var tabs: [[String: Any]] = []
                for snapshot in snapshots {
                    for container in liveContainers(for: snapshot.tabManager) {
                        for tab in container.tabs {
                            tabs.append([
                                "tabID": tab.id.uuidString,
                                "windowID": snapshot.id.uuidString,
                                "url": tab.url.absoluteString,
                                "title": tab.title,
                                "isActive": tab.id == snapshot.tabManager.activeTab?.id
                            ])
                        }
                    }
                }
                return HarnessHTTPResponse.json(tabs)

            case ("POST", "/navigate"):
                guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let urlString = payload["url"] as? String,
                      let url = URL(string: urlString)
                else {
                    return HarnessHTTPResponse.error("body must be {\"url\": \"...\"}", status: 400)
                }
                if let tabRaw = payload["tabID"] as? String {
                    guard let tabID = UUID(uuidString: tabRaw),
                          let found = DebugHarnessRegistry.shared.findTab(tabID)
                    else {
                        return HarnessHTTPResponse.error("unknown tab", status: 404)
                    }
                    let escaped = url.absoluteString
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    found.tab.browserPage?.evaluateJavaScript("location.assign('\(escaped)')")
                    return HarnessHTTPResponse.json(["tabID": found.tab.id.uuidString])
                }
                guard let snapshot = DebugHarnessRegistry.shared.snapshots().first else {
                    return HarnessHTTPResponse.error("no windows registered", status: 404)
                }
                let newTab = snapshot.tabManager.openTab(
                    url: url,
                    historyManager: snapshot.historyManager,
                    focusAfterOpening: true,
                    isPrivate: snapshot.isPrivate
                )
                guard let newTab else {
                    return HarnessHTTPResponse.error("openTab returned nil (no active container?)", status: 500)
                }
                return HarnessHTTPResponse.json(["tabID": newTab.id.uuidString])

            case ("POST", "/eval"):
                return await handleEval(request)

            case ("POST", "/screenshot"):
                return await handleScreenshot(request)

            default:
                return HarnessHTTPResponse.error("no route for \(request.method) \(request.path)", status: 404)
            }
        }

        @MainActor
        private static func handleEval(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let tabRaw = payload["tabID"] as? String,
                  let tabID = UUID(uuidString: tabRaw),
                  let script = payload["js"] as? String
            else {
                return HarnessHTTPResponse.error("body must be {\"tabID\", \"js\"}", status: 400)
            }
            guard let found = DebugHarnessRegistry.shared.findTab(tabID),
                  let page = found.tab.browserPage
            else {
                return HarnessHTTPResponse.error("unknown tab or no page", status: 404)
            }
            do {
                let outcome: Swift.Result<Any?, Error> = try await Self.harnessTimeout(seconds: 5) {
                    await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            page.evaluateJavaScript(script) { value, error in
                                if let error {
                                    continuation.resume(returning: Swift.Result.failure(error))
                                } else {
                                    continuation.resume(returning: Swift.Result.success(value))
                                }
                            }
                        }
                    }
                }
                switch outcome {
                case let .success(value):
                    return HarnessHTTPResponse.json(["result": Self.jsonSafe(value)])
                case let .failure(error):
                    return HarnessHTTPResponse.json([
                        "error": error.localizedDescription,
                        "jsException": true
                    ])
                }
            } catch {
                return HarnessHTTPResponse.error("eval timed out", status: 504)
            }
        }

        @MainActor
        private static func handleScreenshot(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let scope = payload["scope"] as? String,
                  let path = payload["path"] as? String,
                  path.hasPrefix("/")
            else {
                return HarnessHTTPResponse.error(
                    "body must be {\"scope\": \"page\"|\"window\", \"path\": \"/abs.png\"}",
                    status: 400
                )
            }
            switch scope {
            case "page":
                return await handlePageScreenshot(payload: payload, path: path)
            case "window":
                return handleWindowScreenshot(path: path)
            default:
                return HarnessHTTPResponse.error("scope must be page or window", status: 400)
            }
        }

        @MainActor
        private static func handlePageScreenshot(payload: [String: Any], path: String) async -> HarnessHTTPResponse {
            guard let tabRaw = payload["tabID"] as? String,
                  let tabID = UUID(uuidString: tabRaw),
                  let found = DebugHarnessRegistry.shared.findTab(tabID),
                  let page = found.tab.browserPage
            else {
                return HarnessHTTPResponse.error("page scope needs a valid tabID", status: 404)
            }
            let image: NSImage? = await withCheckedContinuation { continuation in
                page.takeSnapshot(
                    configuration: BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: true)
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }
            guard let image else {
                return HarnessHTTPResponse.error("snapshot failed", status: 500)
            }
            return Self.writePNG(image: image, to: path)
        }

        @MainActor
        private static func handleWindowScreenshot(path: String) -> HarnessHTTPResponse {
            guard let window = NSApp.windows
                .first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }),
                let view = window.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else {
                return HarnessHTTPResponse.error("no visible window", status: 404)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                return HarnessHTTPResponse.error("png encode failed", status: 500)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
            } catch {
                return HarnessHTTPResponse.error("write failed: \(error.localizedDescription)", status: 500)
            }
            return HarnessHTTPResponse.json([
                "path": path,
                "width": Int(rep.pixelsWide),
                "height": Int(rep.pixelsHigh)
            ])
        }
    }
#endif
