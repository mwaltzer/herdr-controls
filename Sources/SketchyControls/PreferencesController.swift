import Foundation
import HerdrCore

/// Single owner of the live `HerdrPreferences` value. Reads are lock-guarded
/// so background discovery tasks can consume preferences safely; mutations go
/// through `update`, which persists to disk and notifies main-thread
/// observers (hotkey re-registration, status-item cadence, settings UI).
final class PreferencesController: @unchecked Sendable {
    static let shared = PreferencesController(
        store: JSONFilePreferencesStore(url: HerdrPreferences.defaultStoreURL)
    )

    private let lock = NSLock()
    private let store: any HerdrPreferencesStore
    private var value: HerdrPreferences
    private var observers: [UUID: @MainActor (HerdrPreferences) -> Void] = [:]
    private(set) var lastSaveError: String?

    init(store: any HerdrPreferencesStore) {
        self.store = store
        value = HerdrPreferences.load(from: store)
    }

    var current: HerdrPreferences {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Applies `transform`, saves, and notifies observers. A failed save keeps
    /// the in-memory value (the UI stays consistent) and records the error for
    /// the settings window to surface.
    @discardableResult
    func update(_ transform: (inout HerdrPreferences) -> Void) -> HerdrPreferences {
        lock.lock()
        transform(&value)
        let updated = value
        do {
            try updated.save(to: store)
            lastSaveError = nil
        } catch {
            lastSaveError = String(describing: error)
        }
        let handlers = Array(observers.values)
        lock.unlock()

        Task { @MainActor in
            for handler in handlers { handler(updated) }
        }
        return updated
    }

    /// Registers a main-thread observer called after every successful update.
    /// Keep the returned token alive; `removeObserver` cancels it.
    @discardableResult
    func observe(_ handler: @escaping @MainActor (HerdrPreferences) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        observers[token] = handler
        lock.unlock()
        return token
    }

    func removeObserver(_ token: UUID) {
        lock.lock()
        observers.removeValue(forKey: token)
        lock.unlock()
    }
}
