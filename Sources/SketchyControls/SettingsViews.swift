import AppKit
import HerdrCore
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    private let refreshChoices: [TimeInterval] = [10, 15, 30, 60, 120, 300]

    var body: some View {
        Form {
            shortcutSection
            terminalSection
            panelSection
            macOSSection
            tailnetSection
            diagnosticsSection

            if let saveError = model.saveError {
                Section {
                    Label("Could not save settings: \(saveError)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 480)
    }

    private var macOSSection: some View {
        Section("macOS") {
            Toggle("Launch at login", isOn: model.bind(\.launchAtLogin))
            Toggle("Notify when agents finish or need attention", isOn: model.bind(\.agentNotificationsEnabled))
            Text("Notifications include the workspace and session title, never prompt contents.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutSection: some View {
        Section("Shortcut") {
            HStack {
                Text("Toggle Herdr panel")
                Spacer()
                Button(model.isRecordingHotKey ? "Press keys… (esc cancels)" : model.preferences.herdrPanelHotKey.display) {
                    model.isRecordingHotKey ? model.endRecordingHotKey() : model.beginRecordingHotKey()
                }
                .accessibilityLabel("Record Herdr panel shortcut")
                .accessibilityValue(model.preferences.herdrPanelHotKey.display)
            }
            if let hotKeyError = model.hotKeyError {
                Text(hotKeyError).font(.callout).foregroundStyle(.yellow)
            }
        }
    }

    private var terminalSection: some View {
        Section("Remote sessions") {
            Picker("Terminal", selection: model.bind(\.terminalApp)) {
                ForEach(HerdrTerminal.allCases, id: \.rawValue) { terminal in
                    Text(terminal.rawValue).tag(terminal.rawValue)
                }
                if HerdrTerminal(rawValue: model.preferences.terminalApp) == nil {
                    Text("\(model.preferences.terminalApp) (unsupported — uses Ghostty)")
                        .tag(model.preferences.terminalApp)
                }
            }
            Text("Used when opening a tailnet session. Unsupported values fall back to Ghostty.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var panelSection: some View {
        Section("Herdr panel") {
            Picker("Opens showing", selection: model.bind(\.defaultLocation)) {
                Text("This Mac").tag(HerdrLocation.local)
                Text("Tailnet").tag(HerdrLocation.tailnet)
            }
            Picker("Default list", selection: model.bind(\.defaultTargetKind)) {
                Text("Workspaces / Hosts").tag(HerdrTargetKind.containers)
                Text("Agents").tag(HerdrTargetKind.agents)
            }
            Picker("Refresh sessions every", selection: model.bind(\.refreshInterval)) {
                ForEach(refreshIntervalChoices, id: \.self) { seconds in
                    Text(refreshLabel(seconds)).tag(seconds)
                }
            }
        }
    }

    private var refreshIntervalChoices: [TimeInterval] {
        var choices = refreshChoices
        if !choices.contains(model.preferences.refreshInterval) {
            choices.append(model.preferences.refreshInterval)
            choices.sort()
        }
        return choices
    }

    private func refreshLabel(_ seconds: TimeInterval) -> String {
        seconds < 60
            ? "\(Int(seconds)) seconds"
            : "\(Int(seconds / 60)) minute\(seconds == 60 ? "" : "s")"
    }

    private var tailnetSection: some View {
        Section("Tailnet") {
            Toggle("Discover tailnet sessions", isOn: model.bind(\.tailnetDiscoveryEnabled))

            if model.preferences.tailnetDiscoveryEnabled {
                if model.hostsLoading, model.hostRows.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for hosts…").foregroundStyle(.secondary)
                    }
                }
                ForEach(model.hostRows, id: \.self) { host in
                    Toggle(host, isOn: Binding(
                        get: { !model.preferences.isHostHidden(host) },
                        set: { model.setHost(host, hidden: !$0) }
                    ))
                    .accessibilityLabel("Show sessions from \(host)")
                }
                HStack {
                    TextField("Hide another host…", text: $model.newHiddenHost)
                        .onSubmit { model.addHiddenHost() }
                        .onChange(of: model.newHiddenHost) { _, _ in model.clearHostError() }
                    Button("Hide") { model.addHiddenHost() }
                        .disabled(model.newHiddenHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let hostError = model.hostError {
                    Text(hostError).font(.callout).foregroundStyle(.yellow)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Support") {
            Button {
                model.copyDiagnostics()
            } label: {
                Label(
                    model.diagnosticsCopying ? "Collecting diagnostics…" : model.diagnosticsCopied ? "Diagnostics copied" : "Copy diagnostics",
                    systemImage: model.diagnosticsCopied ? "checkmark.circle.fill" : "doc.on.doc"
                )
            }
            .disabled(model.diagnosticsCopying)
            Text("Includes versions, tool paths, counts, and the last local discovery error. Hostnames and session titles are omitted.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Show Welcome Window", systemImage: "sparkles") {
                OnboardingWindowController.shared.show()
            }
        }
    }
}
