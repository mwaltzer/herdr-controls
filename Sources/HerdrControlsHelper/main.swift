import Foundation
import SketchyControlsCore

enum HelperError: Error {
    case invalidPayload
}

@main
enum HerdrControlsHelper {
    static func main() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let command = CommandLine.arguments.dropFirst().first
            ?? (executable.contains("tailnet-sessions") ? "tailnet-sessions" : "")

        do {
            switch command {
            case "tailnet-sessions":
                try printJSON(tailnetSessions())
            case "report-vcs":
                try reportVCSMetadata()
            default:
                fputs("usage: HerdrControlsHelper <tailnet-sessions|report-vcs>\n", stderr)
                exit(64)
            }
        } catch {
            if command == "tailnet-sessions" {
                print("[]")
                exit(0)
            }
            fputs("Herdr Controls helper failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func tailnetSessions() throws -> [[String: Any]] {
        let cacheURL = cacheDirectory().appendingPathComponent("tailnet-sessions.json")
        if let cached = freshCache(at: cacheURL, maxAge: 10) {
            return cached
        }

        guard let statusData = run("tailscale", ["status", "--json"], timeout: 4),
              let status = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]
        else {
            return readArray(at: cacheURL) ?? []
        }

        let selfName = (status["Self"] as? [String: Any])?["HostName"] as? String
        let peers: [[String: Any]]
        if let values = status["Peer"] as? [String: [String: Any]] {
            peers = Array(values.values)
        } else {
            peers = status["Peer"] as? [[String: Any]] ?? []
        }

        let candidates = peers.compactMap { peer -> [String: Any]? in
            guard peer["Online"] as? Bool == true,
                  let host = peer["HostName"] as? String,
                  host != selfName,
                  validHost(host),
                  let os = peer["OS"] as? String,
                  os == "macOS" || os == "linux"
            else { return nil }
            return [
                "host": host,
                "dns_name": peer["DNSName"] as? String ?? "",
                "tailnet_ip": (peer["TailscaleIPs"] as? [String])?.first ?? "",
                "os": os,
                "last_seen": peer["LastSeen"] as? String ?? "",
            ]
        }

        let lock = NSLock()
        var results: [[String: Any]] = []
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            var result = candidates[index]
            let host = result["host"] as! String
            if let payload = run(
                "ssh",
                ["-o", "BatchMode=yes", "-o", "ConnectTimeout=2", host, "$HOME/.local/bin/herdr api snapshot"],
                timeout: 4
            ),
               let envelope = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
               let response = envelope["result"] as? [String: Any],
               let snapshot = response["snapshot"] as? [String: Any] {
                result["connection_status"] = "online"
                result["agents"] = snapshot["agents"] as? [[String: Any]] ?? []
                result["workspaces"] = snapshot["workspaces"] as? [[String: Any]] ?? []
            } else {
                result["connection_status"] = "unreachable"
                result["agents"] = []
                result["workspaces"] = []
            }
            lock.lock()
            results.append(result)
            lock.unlock()
        }

        results.sort { ($0["host"] as? String ?? "") < ($1["host"] as? String ?? "") }
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        try data.write(to: cacheURL, options: .atomic)
        return results
    }

    private static func reportVCSMetadata() throws {
        guard let data = run("herdr", ["api", "snapshot"], timeout: 5),
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = envelope["result"] as? [String: Any],
              let snapshot = result["snapshot"] as? [String: Any],
              let workspaces = snapshot["workspaces"] as? [[String: Any]],
              let panes = snapshot["panes"] as? [[String: Any]]
        else { throw HelperError.invalidPayload }

        for workspace in workspaces {
            guard let workspaceID = workspace["workspace_id"] as? String else { continue }
            let cwd = panes.first {
                ($0["workspace_id"] as? String) == workspaceID
            }.flatMap {
                ($0["foreground_cwd"] as? String) ?? ($0["cwd"] as? String)
            }
            guard let cwd, !cwd.isEmpty else { continue }

            var tokens: [String: String] = [:]
            if runString("jj", ["-R", cwd, "root"]) != nil {
                tokens["vcs_provider"] = "jj"
                tokens["vcs_ref"] = nonEmpty(runString(
                    "jj",
                    ["-R", cwd, "log", "--ignore-working-copy", "--no-graph", "-r", "@", "-T", "bookmarks.join(\", \")"]
                )) ?? runString(
                    "jj",
                    ["-R", cwd, "log", "--ignore-working-copy", "--no-graph", "-r", "@", "-T", "commit_id.short(8)"]
                )
                tokens["vcs_change"] = runString(
                    "jj",
                    ["-R", cwd, "log", "--ignore-working-copy", "--no-graph", "-r", "@", "-T", "change_id.shortest(8)"]
                )
                tokens["vcs_dirty"] = runString(
                    "jj",
                    ["-R", cwd, "log", "--ignore-working-copy", "--no-graph", "-r", "@", "-T", "empty"]
                ) == "true" ? "false" : "true"
            } else if runString("git", ["-C", cwd, "rev-parse", "--show-toplevel"]) != nil {
                tokens["vcs_provider"] = "git"
                tokens["vcs_ref"] = runString("git", ["-C", cwd, "symbolic-ref", "--quiet", "--short", "HEAD"])
                    ?? runString("git", ["-C", cwd, "rev-parse", "--short", "HEAD"])
                tokens["vcs_change"] = runString("git", ["-C", cwd, "rev-parse", "--short", "HEAD"])
                tokens["vcs_dirty"] = runString("git", ["-C", cwd, "status", "--porcelain=v1"])?.isEmpty == true
                    ? "false" : "true"
            }

            var arguments = ["workspace", "report-metadata", workspaceID, "--source", "controls_vcs"]
            if tokens.isEmpty {
                for key in ["vcs_provider", "vcs_ref", "vcs_change", "vcs_dirty"] {
                    arguments += ["--clear-token", key]
                }
            } else {
                for (key, value) in tokens.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
                    arguments += ["--token", "\(key)=\(value)"]
                }
            }
            _ = run("herdr", arguments, timeout: 5)
        }
    }

    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        guard let resolved = resolve(executable) else { return nil }
        let result = BoundedProcess.run(
            executable: resolved,
            arguments: arguments,
            timeout: timeout,
            outputLimit: 4 * 1_024 * 1_024,
            environment: executable == "tailscale" ? ["TAILSCALE_BE_CLI": "1"] : nil
        )
        guard let result, !result.timedOut, result.terminationStatus == 0 else { return nil }
        return result.output
    }

    private static func resolve(_ executable: String) -> String? {
        let home = NSHomeDirectory()
        var candidates: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/\(executable)" }
        }
        switch executable {
        case "herdr":
            candidates += [
                "\(home)/.local/bin/herdr",
                "\(home)/.local/share/mise/shims/herdr",
                "/opt/homebrew/bin/herdr",
                "/usr/local/bin/herdr",
            ]
        case "tailscale":
            candidates += [
                "/opt/homebrew/bin/tailscale",
                "/usr/local/bin/tailscale",
                "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            ]
        case "jj":
            candidates += [
                "\(home)/.local/bin/jj",
                "\(home)/.local/share/mise/shims/jj",
                "/opt/homebrew/bin/jj",
                "/usr/local/bin/jj",
            ]
        case "git":
            candidates += ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        case "ssh":
            candidates += ["/usr/bin/ssh"]
        default:
            break
        }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    private static func runString(_ executable: String, _ arguments: [String]) -> String? {
        guard let data = run(executable, arguments, timeout: 3),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func validHost(_ host: String) -> Bool {
        host.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil
    }

    private static func cacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("HerdrControls") }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("HerdrControls")
    }

    private static func freshCache(at url: URL, maxAge: TimeInterval) -> [[String: Any]]? {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              Date().timeIntervalSince(date) < maxAge
        else { return nil }
        return readArray(at: url)
    }

    private static func readArray(at url: URL) -> [[String: Any]]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    private static func printJSON(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
