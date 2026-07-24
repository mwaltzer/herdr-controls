import Foundation

public enum HerdrDiagnostics {
    /// `snapshot.localStatus` must contain a user-facing category, never raw
    /// process stderr or payload text. Discovery enforces this by translating
    /// contract errors through `HerdrContractError.userDescription`.
    public static func report(
        snapshot: HerdrSnapshot,
        preferences: HerdrPreferences,
        appVersion: String,
        operatingSystem: String
    ) -> String {
        let localStatus: String
        switch snapshot.localStatus {
        case .notLoaded:
            localStatus = "not loaded"
        case .ok:
            localStatus = "available"
        case let .unavailable(reason):
            localStatus = "unavailable (\(reason))"
        }

        let remoteAgentCount = snapshot.remoteHosts.reduce(0) { $0 + $1.agents.count }
        return """
        Herdr Controls diagnostics
        App version: \(appVersion)
        Operating system: \(operatingSystem)
        Local contract: v\(HerdrContract.localVersion)
        Tailnet contract: v\(HerdrContract.tailnetVersion)
        Local status: \(localStatus)
        Local workspaces: \(snapshot.workspaces.count)
        Local agents: \(snapshot.agents.count)
        Tailnet hosts: \(snapshot.remoteHosts.count)
        Tailnet agents: \(remoteAgentCount)
        Tailnet discovery: \(preferences.tailnetDiscoveryEnabled ? "enabled" : "disabled")
        Hidden hosts: \(preferences.hiddenHosts.count)
        Herdr executable: \(redactedPath(preferences.herdrExecutable))
        Tailnet helper: \(redactedPath(preferences.tailnetSessionsExecutable))
        Open helper: \(redactedPath(preferences.openTailnetSessionExecutable))
        Terminal: \(HerdrTerminal(rawValue: preferences.terminalApp)?.rawValue ?? "unsupported")
        Refresh interval: \(Int(preferences.refreshInterval)) seconds
        """
    }

    private static func redactedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
