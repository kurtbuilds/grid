import Carbon.HIToolbox
import GridCore

/// System-wide hotkey via Carbon's RegisterEventHotKey. Needs no special permission
/// and fires even while another app is focused (or while our overlay is open).
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: (() -> Void)?
    private(set) var combo: KeyCombo?
    private var hotKeyRef: EventHotKeyRef?
    private var suspendCount = 0

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// Returns false if the combo is already taken by another app or the system.
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        self.combo = combo
        return suspendCount > 0 ? true : install()
    }

    /// Temporarily releases the hotkey (e.g. while recording a new shortcut).
    func suspend() {
        suspendCount += 1
        if suspendCount == 1 { uninstall() }
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        if suspendCount == 0 { install() }
    }

    @discardableResult
    private func install() -> Bool {
        uninstall()
        guard let combo else { return false }
        let id = EventHotKeyID(signature: OSType(0x4752_4944) /* 'GRID' */, id: 1)
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    private func uninstall() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
