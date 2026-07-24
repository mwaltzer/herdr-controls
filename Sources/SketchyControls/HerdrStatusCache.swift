import Foundation
import HerdrCore

private struct CachedHerdrStatus: Codable {
    let version: Int
    let available: Bool
    let agentCount: Int
    let maxAgeSeconds: Int
}

enum HerdrStatusCache {
    private static let url = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first?
        .appendingPathComponent("HerdrControls", isDirectory: true)
        .appendingPathComponent("status.json")

    static func write(_ snapshot: HerdrSnapshot, refreshInterval: TimeInterval) {
        guard let url else { return }
        let remoteAgents = snapshot.remoteHosts.reduce(0) { $0 + $1.agents.count }
        let status = CachedHerdrStatus(
            version: 1,
            available: snapshot.available,
            agentCount: snapshot.agents.count + remoteAgents,
            maxAgeSeconds: max(90, Int(refreshInterval * 2) + 10)
        )
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
