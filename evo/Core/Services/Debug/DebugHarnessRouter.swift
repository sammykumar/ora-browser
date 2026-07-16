#if DEBUG
    import Foundation
    import SwiftData

    enum DebugHarnessRouter {
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

            default:
                return HarnessHTTPResponse.error("no route for \(request.method) \(request.path)", status: 404)
            }
        }
    }
#endif
