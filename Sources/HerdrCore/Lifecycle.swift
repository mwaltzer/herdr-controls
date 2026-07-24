import Foundation

/// Connection lifecycle for a discovery source (local CLI or a tailnet host).
/// The UI derives messaging from this instead of a bare boolean, so failures
/// can say what broke and when a retry is due.
public enum HerdrConnectionState: Equatable, Sendable {
    case idle
    case refreshing
    case connected
    case failed(attempt: Int, reason: String)
}

/// Deterministic exponential backoff. No jitter by design: the schedule stays
/// reproducible in checks, and discovery polls are cheap local processes.
public struct RetryPolicy: Equatable, Sendable {
    public var initialDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval
    public var maxAttempts: Int?

    public init(initialDelay: TimeInterval, multiplier: Double, maxDelay: TimeInterval, maxAttempts: Int? = nil) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }

    /// Session discovery keeps retrying forever: a dead herdr daemon coming
    /// back should repopulate the panel without relaunching the app.
    public static let sessionDiscovery = RetryPolicy(initialDelay: 1, multiplier: 2, maxDelay: 30)

    /// Delay before retry number `attempt` (1-based). Values below 1 are
    /// treated as the first attempt.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let delay = initialDelay * pow(multiplier, Double(exponent))
        return min(delay, maxDelay)
    }

    public func shouldRetry(attempt: Int) -> Bool {
        guard let maxAttempts else { return true }
        return attempt < maxAttempts
    }

    /// Backoff for the automatic in-panel retry loop: 1→2→4→8→16 s, then stop
    /// and let the app shell's cadence timer keep checking. Bounded so a dead
    /// herdr install doesn't run two refresh trains forever.
    public static let panelRetry = RetryPolicy(initialDelay: 1, multiplier: 2, maxDelay: 16, maxAttempts: 6)
}

/// Pure fold of discovery results into a connection state with retry
/// scheduling. The owner feeds every snapshot through `updating(with:policy:)`
/// and schedules a retry after `retryDelay` when it is non-nil.
public struct HerdrDiscoveryHealth: Equatable, Sendable {
    public var state: HerdrConnectionState
    public var consecutiveFailures: Int
    /// Delay before the next automatic retry; nil when connected, still
    /// loading, or the policy is exhausted.
    public var retryDelay: TimeInterval?

    public init(state: HerdrConnectionState = .idle, consecutiveFailures: Int = 0, retryDelay: TimeInterval? = nil) {
        self.state = state
        self.consecutiveFailures = consecutiveFailures
        self.retryDelay = retryDelay
    }

    public func updating(with snapshot: HerdrSnapshot, policy: RetryPolicy) -> HerdrDiscoveryHealth {
        switch snapshot.localStatus {
        case .notLoaded:
            return HerdrDiscoveryHealth(state: .refreshing, consecutiveFailures: consecutiveFailures)
        case .ok:
            return HerdrDiscoveryHealth(state: .connected)
        case let .unavailable(reason):
            let attempt = consecutiveFailures + 1
            return HerdrDiscoveryHealth(
                state: .failed(attempt: attempt, reason: reason),
                consecutiveFailures: attempt,
                retryDelay: policy.shouldRetry(attempt: attempt) ? policy.delay(forAttempt: attempt) : nil
            )
        }
    }

    public var failureReason: String? {
        if case let .failed(_, reason) = state { return reason }
        return nil
    }
}

/// What the Herdr panel should show for the current scope when the selected
/// list has nothing to offer; nil means the selected (location, kind) list has
/// content to render. Kind matters: workspaces can exist while zero agents are
/// attached, and the Agents list must say so instead of going blank.
public enum HerdrPanelIssue: Equatable, Sendable {
    case loading
    case localUnavailable(reason: String)
    case noLocalSessions
    /// Local workspaces may exist; the selected Agents list is empty.
    case noLocalAgents
    case tailnetDisabled
    case noTailnetSessions
    /// Tailnet hosts responded but reported no agents for the Agents list.
    case noTailnetAgents
}

public enum HerdrPanelStatus {
    public static func issue(
        snapshot: HerdrSnapshot,
        location: HerdrLocation,
        kind: HerdrTargetKind,
        tailnetDiscoveryEnabled: Bool
    ) -> HerdrPanelIssue? {
        switch location {
        case .local:
            switch snapshot.localStatus {
            case .notLoaded:
                return .loading
            case let .unavailable(reason):
                return .localUnavailable(reason: reason)
            case .ok:
                switch kind {
                case .containers:
                    return snapshot.workspaces.isEmpty ? .noLocalSessions : nil
                case .agents:
                    return snapshot.agents.isEmpty ? .noLocalAgents : nil
                }
            }
        case .tailnet:
            guard tailnetDiscoveryEnabled else { return .tailnetDisabled }
            if snapshot.remoteHosts.isEmpty {
                return snapshot.localStatus == .notLoaded ? .loading : .noTailnetSessions
            }
            if kind == .agents, snapshot.remoteHosts.allSatisfy(\.agents.isEmpty) { return .noTailnetAgents }
            return nil
        }
    }
}
