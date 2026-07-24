import AppKit
import HerdrCore
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var report: HerdrEnvironmentReport
    @Published private(set) var sketchyBarDetected = false
    @Published private(set) var preferences: HerdrPreferences

    private let controller: PreferencesController

    init(controller: PreferencesController = .shared) {
        self.controller = controller
        let current = controller.current
        preferences = current
        report = Self.evaluateReport(for: current)
        sketchyBarDetected = Self.detectSketchyBar()
        controller.observe { [weak self] updated in
            self?.preferences = updated
        }
    }

    func refresh() {
        preferences = controller.current
        report = Self.evaluateReport(for: preferences)
        sketchyBarDetected = Self.detectSketchyBar()
    }

    func complete() {
        controller.update { $0.onboardingCompleted = true }
    }

    private static func evaluateReport(for preferences: HerdrPreferences) -> HerdrEnvironmentReport {
        HerdrEnvironmentReport.evaluate(preferences: preferences) {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// The adapter is optional: presence of the sketchybar binary or its
    /// config directory is enough to mention the integration.
    private static func detectSketchyBar() -> Bool {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/sketchybar",
            "/usr/local/bin/sketchybar",
            home + "/.nix-profile/bin/sketchybar",
            "/run/current-system/sw/bin/sketchybar",
        ]
        if candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return true }
        return FileManager.default.fileExists(atPath: home + "/.config/sketchybar/sketchybarrc")
    }
}

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private let model = OnboardingModel()
    private var window: NSWindow?

    /// First-run gate: shows the welcome window until the user completes it.
    func showIfNeeded() {
        guard !PreferencesController.shared.current.onboardingCompleted else { return }
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: OnboardingRootView(model: model) { [weak self] in
                    self?.model.complete()
                    self?.window?.orderOut(nil)
                }
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to Herdr Controls"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 480, height: 620))
            window.center()
            self.window = window
        }
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct OnboardingRootView: View {
    @ObservedObject var model: OnboardingModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                header
                componentsSection
                shortcutSection
                tailnetSection
                sketchyBarSection
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Herdr sessions from your menu bar")
                    .font(.title3.weight(.semibold))
                Text("See and switch to Herdr agents and workspaces on this Mac and across your tailnet — from the menu bar icon or a global shortcut.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var componentsSection: some View {
        Section("Components") {
            ForEach(model.report.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: item.available ? "checkmark.circle.fill" : (item.required ? "xmark.circle.fill" : "minus.circle"))
                        .foregroundStyle(item.available ? .green : (item.required ? .red : .secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.available ? item.detail : "Not found at \(item.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !model.report.ready {
                Text("Herdr Controls still runs without the missing pieces, but the related features stay empty until they are installed.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Check Again", systemImage: "arrow.clockwise") { model.refresh() }
        }
    }

    private var shortcutSection: some View {
        Section("Shortcut") {
            LabeledContent("Toggle the Herdr panel") {
                Text(model.preferences.herdrPanelHotKey.display)
                    .font(.body.monospaced())
            }
            Text("Works anywhere. Change it later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tailnetSection: some View {
        Section("Tailnet") {
            LabeledContent("Discovery") {
                Text(model.preferences.tailnetDiscoveryEnabled ? "On" : "Off")
            }
            Text("Herdr Controls asks your online tailnet machines for their sessions over SSH — using your own keys, nothing else. Hide individual hosts or turn discovery off in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sketchyBarSection: some View {
        Section("SketchyBar (optional)") {
            LabeledContent("Adapter") {
                Text(model.sketchyBarDetected ? "Detected" : "Not detected")
            }
            Text(model.sketchyBarDetected
                ? "Your SketchyBar setup can keep driving these panels through the sketchy-controls CLI. Nothing to configure here."
                : "Not needed — the menu bar icon and shortcut cover everything. SketchyBar users can drive the same panels through the sketchy-controls CLI.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Settings…") {
                SettingsWindowController.shared.show()
            }
            Spacer()
            Button("Get Started") { finish() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
