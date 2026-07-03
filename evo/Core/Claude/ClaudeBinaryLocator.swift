import Foundation

enum ClaudeBinaryLocator {
    enum LocatorError: Error, Equatable { case notFound }

    static func resolve(override: String?, runWhich: () -> String?) -> Swift.Result<String, LocatorError> {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return .success(override)
        }
        if let found = runWhich(), !found.isEmpty { return .success(found) }
        return .failure(.notFound)
    }

    static func resolve() -> Swift.Result<String, LocatorError> {
        resolve(
            override: UserDefaults.standard.string(forKey: "claude.binaryPath"),
            runWhich: {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", "which claude"]
                let out = Pipe()
                p.standardOutput = out
                do { try p.run() } catch { return nil }
                p.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (s?.isEmpty == false) ? s : nil
            }
        )
    }
}
