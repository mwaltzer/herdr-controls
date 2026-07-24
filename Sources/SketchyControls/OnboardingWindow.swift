import AppKit
import HerdrCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case readiness
    case preferences
    case complete
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var report: HerdrEnvironmentReport
    @Published private(set) var sketchyBarDetected = false
    @Published private(set) var preferences: HerdrPreferences
    @Published var step: OnboardingStep = .welcome

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

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func setTailnetDiscovery(_ enabled: Bool) {
        preferences = controller.update { $0.tailnetDiscoveryEnabled = enabled }
        report = Self.evaluateReport(for: preferences)
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
            window.setContentSize(NSSize(width: 560, height: 620))
            window.center()
            self.window = window
        }
        model.refresh()
        model.step = .welcome
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct OnboardingRootView: View {
    @ObservedObject var model: OnboardingModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(minWidth: 520, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            HerdrOnboardingLogo(size: 34)
            Text("Herdr Controls")
                .font(.headline)
            Spacer()
            Text("\(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .frame(height: 62)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            welcomeStep
        case .readiness:
            readinessStep
        case .preferences:
            preferencesStep
        case .complete:
            completeStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your Herdr sessions, one shortcut away.")
                    .font(.system(size: 28, weight: .semibold))
                Text("Move between local and remote work without hunting through terminal windows.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                onboardingFeature(
                    icon: "rectangle.3.group",
                    title: "See the work that is running",
                    detail: "Browse workspaces and their attached agents in one compact panel."
                )
                onboardingFeature(
                    icon: "keyboard",
                    title: "Navigate without leaving the keyboard",
                    detail: "Open Herdr with \(model.preferences.herdrPanelHotKey.display), then use J, K, H, and L."
                )
                onboardingFeature(
                    icon: "network",
                    title: "Reach sessions across your tailnet",
                    detail: "Open a remote agent over SSH in your preferred terminal."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(32)
    }

    private var readinessStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeading(
                "Check your setup",
                detail: "Herdr is required. Tailnet helpers are optional and only affect remote sessions."
            )

            VStack(spacing: 8) {
                ForEach(model.report.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.available ? "checkmark.circle.fill" : (item.required ? "xmark.circle.fill" : "minus.circle"))
                        .foregroundStyle(item.available ? .green : (item.required ? .red : .secondary))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.title).fontWeight(.medium)
                            Spacer()
                            Text(item.required ? "Required" : "Optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.available ? item.detail : "Not found at \(item.path)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            }

            if !model.report.ready {
                Label(
                    "You can continue, but local sessions remain unavailable until Herdr is installed.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            Button("Check Again", systemImage: "arrow.clockwise") {
                model.refresh()
            }
            .controlSize(.small)

            Spacer()
        }
        .padding(32)
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeading(
                "Choose how Herdr behaves",
                detail: "These defaults can be changed anytime from the settings button."
            )

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global shortcut").fontWeight(.medium)
                        Text("Opens the Herdr panel from anywhere.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.preferences.herdrPanelHotKey.display)
                        .font(.body.monospaced().weight(.medium))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(14)

                Divider().padding(.leading, 46)

                HStack(spacing: 14) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tailnet discovery").fontWeight(.medium)
                        Text("Find remote Herdr sessions over SSH.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.preferences.tailnetDiscoveryEnabled },
                        set: { model.setTailnetDiscovery($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(14)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 12) {
                Image(systemName: model.sketchyBarDetected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.sketchyBarDetected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.sketchyBarDetected ? "SketchyBar detected" : "SketchyBar not detected")
                        .fontWeight(.medium)
                    Text("Optional. The standalone menu-bar app and shortcut work without it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
        .padding(32)
    }

    private var completeStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Herdr is ready.")
                    .font(.system(size: 28, weight: .semibold))
                Text("Press \(model.preferences.herdrPanelHotKey.display) to open the panel, then use J and K to move.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Settings remain available from the gear button in the top-right corner of the panel.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(40)
    }

    private var footer: some View {
        HStack {
            if model.step != .welcome {
                Button("Back") {
                    model.goBack()
                }
            }
            Spacer()
            if model.step == .complete {
                Button("Get Started", action: finish)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(model.step == .welcome ? "Continue" : "Next") {
                    model.advance()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(.bar)
    }

    private func stepHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingFeature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HerdrOnboardingLogo: View {
    let size: CGFloat

    private let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "herdr-mask", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}
