import AppKit
import HerdrCore
import SketchyControlsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: IPCServer?
    private var panelController: PanelController?
    private var statusItemController: StatusItemController?
    private var herdrHotKey: GlobalHotKey?
    private var refreshTimer: Timer?
    private var preferencesObserver: UUID?
    private var appliedPreferences: HerdrPreferences?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel()
        model.refresh(.controlCenter)
        let panelController = PanelController(model: model)
        self.panelController = panelController
        statusItemController = StatusItemController(model: model, panelController: panelController)

        apply(PreferencesController.shared.current)
        preferencesObserver = PreferencesController.shared.observe { [weak self] preferences in
            self?.apply(preferences)
        }

        server = IPCServer { [weak self] command in self?.panelController?.handle(command) }
        do { try server?.start() } catch {
            NSApp.terminate(nil)
            return
        }
        OnboardingWindowController.shared.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        herdrHotKey = nil
        if let preferencesObserver {
            PreferencesController.shared.removeObserver(preferencesObserver)
        }
        preferencesObserver = nil
        server = nil
    }

    private func apply(_ preferences: HerdrPreferences) {
        let previous = appliedPreferences
        appliedPreferences = preferences

        if previous?.herdrPanelHotKey != preferences.herdrPanelHotKey {
            registerHotKey(preferences.herdrPanelHotKey)
        }
        if previous?.refreshInterval != preferences.refreshInterval {
            scheduleRefresh(every: preferences.refreshInterval)
        } else if let previous, discoverySettingsChanged(from: previous, to: preferences) {
            refreshHerdr()
        }
    }

    private func discoverySettingsChanged(
        from previous: HerdrPreferences,
        to preferences: HerdrPreferences
    ) -> Bool {
        previous.herdrExecutable != preferences.herdrExecutable
            || previous.tailnetSessionsExecutable != preferences.tailnetSessionsExecutable
            || previous.tailnetDiscoveryEnabled != preferences.tailnetDiscoveryEnabled
            || previous.hiddenHosts != preferences.hiddenHosts
    }

    private func registerHotKey(_ specification: HotKeySpec) {
        herdrHotKey = nil
        guard specification.isValid else { return }
        herdrHotKey = GlobalHotKey(
            keyCode: specification.keyCode,
            modifiers: specification.carbonModifiers
        ) { [weak self] in
            Task { @MainActor in
                self?.statusItemController?.togglePanelFromHotKey()
            }
        }
    }

    private func scheduleRefresh(every interval: TimeInterval) {
        refreshTimer?.invalidate()
        guard interval > 0 else {
            refreshTimer = nil
            return
        }

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshHerdr()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refreshHerdr()
    }

    private func refreshHerdr() {
        guard let model = panelController?.model else { return }
        model.refreshHerdrSnapshot()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
