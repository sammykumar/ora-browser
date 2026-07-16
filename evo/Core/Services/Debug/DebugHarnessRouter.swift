#if DEBUG
    import Foundation

    enum DebugHarnessRouter {
        @MainActor
        static func route(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return HarnessHTTPResponse.json([
                    "ok": true,
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    "pid": Int(ProcessInfo.processInfo.processIdentifier)
                ])
            default:
                return HarnessHTTPResponse.error("no route for \(request.method) \(request.path)", status: 404)
            }
        }
    }
#endif
