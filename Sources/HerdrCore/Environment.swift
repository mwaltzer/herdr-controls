import Foundation

/// First-run readiness report over the executables the app depends on.
/// Executability is injected so the report stays checkable without a real
/// filesystem; the app passes `FileManager` in.
public struct HerdrEnvironmentReport: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String
        public let path: String
        /// Required items gate `ready`; optional ones only degrade features.
        public let required: Bool
        public let available: Bool

        public init(id: String, title: String, detail: String, path: String, required: Bool, available: Bool) {
            self.id = id
            self.title = title
            self.detail = detail
            self.path = path
            self.required = required
            self.available = available
        }
    }

    public let items: [Item]

    public var ready: Bool { items.filter(\.required).allSatisfy(\.available) }
    public var missingRequired: [Item] { items.filter { $0.required && !$0.available } }

    public static func evaluate(
        preferences: HerdrPreferences,
        isExecutable: (String) -> Bool
    ) -> HerdrEnvironmentReport {
        HerdrEnvironmentReport(items: [
            Item(
                id: "herdr-cli",
                title: "herdr CLI",
                detail: "Lists and focuses local workspaces and agents.",
                path: preferences.herdrExecutable,
                required: true,
                available: isExecutable(preferences.herdrExecutable)
            ),
            Item(
                id: "tailnet-helper",
                title: "Tailnet session helper",
                detail: "Discovers Herdr sessions on your other tailnet machines over SSH.",
                path: preferences.tailnetSessionsExecutable,
                required: false,
                available: isExecutable(preferences.tailnetSessionsExecutable)
            ),
            Item(
                id: "open-helper",
                title: "Remote session opener",
                detail: "Attaches your terminal to a remote Herdr session.",
                path: preferences.openTailnetSessionExecutable,
                required: false,
                available: isExecutable(preferences.openTailnetSessionExecutable)
            ),
        ])
    }

    public init(items: [Item]) {
        self.items = items
    }
}
