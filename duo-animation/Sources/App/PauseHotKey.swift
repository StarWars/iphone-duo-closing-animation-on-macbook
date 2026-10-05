import AppKit
import Carbon

@MainActor
final class PauseHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let pause: @MainActor () -> Void
    private(set) var registered = false

    init(pause: @escaping @MainActor () -> Void) {
        self.pause = pause
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x444C6964, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            // Carbon's application event target is handled on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<PauseHotKey>.fromOpaque(context).takeUnretainedValue().pause()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x444C6964, id: 1)
        registered = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey),
                                         identifier, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        registered = false
    }
}
