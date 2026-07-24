import Carbon
import HerdrCore

extension HotKeySpec {
    var carbonModifiers: UInt32 {
        modifiers.reduce(0) { flags, modifier in
            switch modifier {
            case .command: flags | UInt32(cmdKey)
            case .option: flags | UInt32(optionKey)
            case .control: flags | UInt32(controlKey)
            case .shift: flags | UInt32(shiftKey)
            }
        }
    }
}

final class GlobalHotKey {
    private final class ActionBox {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }

    private let box: ActionBox
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        box = ActionBox(action: action)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<ActionBox>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }
        guard InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(box).toOpaque(),
            &handler
        ) == noErr else { return nil }

        let identifier = EventHotKeyID(signature: OSType(0x48445248), id: 1)
        guard RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
