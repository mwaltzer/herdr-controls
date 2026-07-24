import AppIntents
import AppKit

struct ShowHerdrIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Herdr"
    static let description = IntentDescription("Open the Herdr workspace and agent picker.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NSWorkspace.shared.open(URL(string: "herdr-controls://show")!)
        return .result()
    }
}

struct FocusHerdrWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Focus Herdr Workspace"
    static let description = IntentDescription("Focus a Herdr workspace by its stable ID.")
    static let openAppWhenRun = false

    @Parameter(title: "Workspace ID")
    var workspaceID: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let encoded = workspaceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "herdr-controls://workspace/\(encoded)")
        else { return .result() }
        NSWorkspace.shared.open(url)
        return .result()
    }
}

struct OpenHerdrAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Herdr Agent"
    static let description = IntentDescription("Open a Herdr agent by its pane ID.")
    static let openAppWhenRun = false

    @Parameter(title: "Pane ID")
    var paneID: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let encoded = paneID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "herdr-controls://agent/\(encoded)")
        else { return .result() }
        NSWorkspace.shared.open(url)
        return .result()
    }
}
