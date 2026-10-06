import AppKit
import ApplicationServices
import GridCore

struct TargetWindow {
    let window: AXUIElement
    let app: AXUIElement
    let appName: String
}

/// Moves and resizes other apps' windows through the Accessibility API.
enum WindowManager {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Clears Grid's Accessibility entry and asks again. Fixes the case where System Settings
    /// shows Grid switched on but the entry belongs to an older build.
    static func resetTrust() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        try? task.run()
        task.waitUntilExit()
        promptForTrust()
    }

    static func focusedWindow() -> TargetWindow? {
        guard let running = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        let name = running.localizedName ?? "Window"
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let w = element(app, attribute) { return TargetWindow(window: w, app: app, appName: name) }
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement], let first = windows.first {
            return TargetWindow(window: first, app: app, appName: name)
        }
        return nil
    }

    /// Current frame in AppKit coordinates.
    static func frame(of target: TargetWindow) -> CGRect? {
        guard let origin: CGPoint = axValue(target.window, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(target.window, kAXSizeAttribute, .cgSize)
        else { return nil }
        return ScreenGeometry.flip(CGRect(origin: origin, size: size))
    }

    /// Sets a window's frame (AppKit coordinates) instantly.
    static func setFrame(_ frame: CGRect, of target: TargetWindow) {
        let ax = ScreenGeometry.flip(frame)

        // Apps with "enhanced user interface" on (set by VoiceOver and some utilities) animate
        // every AX resize, slowly. Turning it off for the duration of the change makes it instant.
        let enhanced = "AXEnhancedUserInterface" as CFString
        var wasEnhanced = false
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(target.app, enhanced, &value) == .success, let b = value as? Bool, b {
            wasEnhanced = true
            AXUIElementSetAttributeValue(target.app, enhanced, kCFBooleanFalse)
        }
        defer { if wasEnhanced { AXUIElementSetAttributeValue(target.app, enhanced, kCFBooleanTrue) } }

        // Size → position → size: the first resize lets the window fit on the destination before
        // moving (macOS clamps windows that would hang off a display); the second applies the
        // final size in case the move was clamped against the old size.
        set(target.window, kAXSizeAttribute, ax.size)
        set(target.window, kAXPositionAttribute, ax.origin)
        set(target.window, kAXSizeAttribute, ax.size)

        // Some apps report success but end up somewhere else (e.g. they enforce a minimum size
        // and get pushed). If the origin drifted, nudge it back once.
        if let actual: CGPoint = axValue(target.window, kAXPositionAttribute, .cgPoint),
           abs(actual.x - ax.minX) > 1 || abs(actual.y - ax.minY) > 1 {
            set(target.window, kAXPositionAttribute, ax.origin)
        }
    }

    // MARK: - AX helpers

    private static func element(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue<T>(_ el: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axv = value as! AXValue
        guard AXValueGetType(axv) == type else { return nil }
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        return AXValueGetValue(axv, type, ptr) ? ptr.pointee : nil
    }

    private static func set(_ el: AXUIElement, _ attribute: String, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(el, attribute as CFString, v) }
    }

    private static func set(_ el: AXUIElement, _ attribute: String, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, attribute as CFString, v) }
    }
}

/// NSScreen-aware wrappers around GridCore.Geometry.
enum ScreenGeometry {
    /// Height of the primary (menu bar) display, which anchors both coordinate systems.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func flip(_ rect: CGRect) -> CGRect { Geometry.flip(rect, primaryHeight: primaryHeight) }

    /// Displays ordered left to right (then bottom to top), so cycling feels spatial.
    static var orderedScreens: [NSScreen] {
        NSScreen.screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    static func screen(for frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        return Geometry.bestScreenIndex(for: frame, screens: screens.map(\.frame)).map { screens[$0] }
    }

    static var screenWithMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }
}
