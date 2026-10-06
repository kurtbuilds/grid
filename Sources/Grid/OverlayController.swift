import AppKit
import Carbon.HIToolbox
import GridCore

/// A panel that takes keyboard focus without activating our app, so the window being
/// resized keeps focus the whole time.
final class OverlayPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Intercept before key-view-loop / key-equivalent handling so Tab and plain letters reach us.
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Translucent highlight showing where the window will land.
final class PreviewWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        if let layer = view.layer {
            let accent = NSColor.controlAccentColor
            layer.backgroundColor = accent.withAlphaComponent(0.18).cgColor
            layer.borderColor = accent.withAlphaComponent(0.85).cgColor
            layer.borderWidth = 3
            layer.cornerRadius = 12
        }
        contentView = view
    }
}

extension Notification.Name {
    static let gridOverlayOpened = Notification.Name("GridOverlayOpened")
    static let gridWindowSnapped = Notification.Name("GridWindowSnapped")
}

@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    let store: SettingsStore
    let panel: OverlayPanel
    private let preview = PreviewWindow()
    private let effect = NSVisualEffectView()
    let gridView = GridView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    private(set) var target: TargetWindow?
    private(set) var screen: NSScreen?

    var isVisible: Bool { panel.isVisible }
    /// Called when the grid is requested but Accessibility access hasn't been granted.
    var onNeedsPermission: (() -> Void)?

    init(store: SettingsStore) {
        self.store = store
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 18)
        panel.contentView = effect

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        [titleLabel, gridView, hintLabel].forEach(effect.addSubview)

        gridView.onHighlight = { [weak self] rect in self?.updatePreview(rect) }
        gridView.onSelect = { [weak self] rect in self?.applySelection(rect) }
    }

    // MARK: Showing / hiding

    func hotKeyPressed() {
        guard isVisible else { return show() }
        switch store.config.repeatBehavior {
        case .cycleDisplays where NSScreen.screens.count > 1: moveToAdjacentScreen(1)
        default: hide()
        }
    }

    func show() {
        guard WindowManager.isTrusted else {
            onNeedsPermission?()
            return
        }
        target = WindowManager.focusedWindow()
        let frame = target.flatMap(WindowManager.frame(of:))
        screen = frame.flatMap(ScreenGeometry.screen(for:)) ?? ScreenGeometry.screenWithMouse ?? NSScreen.main
        gridView.columns = store.config.columns
        gridView.rows = store.config.rows
        layout()
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .gridOverlayOpened, object: nil)
    }

    func hide() {
        guard isVisible || preview.isVisible else { return }
        panel.orderOut(nil)
        preview.orderOut(nil)
        gridView.reset()
        target = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the overlay.
        hide()
    }

    // MARK: Actions

    private func handleKey(_ event: NSEvent) -> Bool {
        let combo = KeyCombo(event: event)
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
            return true
        case kVK_Tab:
            moveToAdjacentScreen(combo.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        default:
            break
        }
        if event.isARepeat { return true }
        if let shortcut = store.config.shortcut(for: combo) {
            apply(unit: shortcut.unitRect)
        } else {
            NSSound.beep()
        }
        return true
    }

    private func applySelection(_ rect: GridRect) {
        apply(unit: rect.unitRect(columns: gridView.columns, rows: gridView.rows))
    }

    private func apply(unit: CGRect) {
        guard let target, let screen else { return hide() }
        let frame = Geometry.frame(forUnit: unit, in: screen.visibleFrame)
        hide()
        WindowManager.setFrame(frame, of: target)
        NotificationCenter.default.post(name: .gridWindowSnapped, object: nil)
    }

    private func moveToAdjacentScreen(_ step: Int) {
        let screens = ScreenGeometry.orderedScreens
        guard screens.count > 1, let current = screen,
              let index = screens.firstIndex(of: current) else { return }
        let next = screens[(index + step + screens.count) % screens.count]
        if let target, let frame = WindowManager.frame(of: target) {
            WindowManager.setFrame(Geometry.relocate(frame, from: current.visibleFrame, to: next.visibleFrame), of: target)
        }
        screen = next
        gridView.reset()
        preview.orderOut(nil)
        layout()
    }

    private func updatePreview(_ rect: GridRect?) {
        guard store.config.showPreview, let rect, let screen, target != nil else {
            preview.orderOut(nil)
            return
        }
        let unit = rect.unitRect(columns: gridView.columns, rows: gridView.rows)
        preview.setFrame(Geometry.frame(forUnit: unit, in: screen.visibleFrame), display: true)
        preview.order(.below, relativeTo: panel.windowNumber)
    }

    // MARK: Layout

    func layout() {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let maxSide: CGFloat = 420
        let aspect = visible.width / max(visible.height, 1)
        var gridSize = NSSize(width: maxSide, height: (maxSide / aspect).rounded())
        if gridSize.height > maxSide { gridSize = NSSize(width: (maxSide * aspect).rounded(), height: maxSide) }

        let pad: CGFloat = 18, spacing: CGFloat = 12, titleHeight: CGFloat = 18, hintHeight: CGFloat = 15
        let size = NSSize(width: gridSize.width + pad * 2,
                          height: pad + titleHeight + spacing + gridSize.height + spacing + hintHeight + pad)
        let origin = NSPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
        panel.setFrame(NSRect(origin: origin, size: size), display: false)

        hintLabel.frame = NSRect(x: pad, y: pad, width: gridSize.width, height: hintHeight)
        gridView.frame = NSRect(x: pad, y: pad + hintHeight + spacing, width: gridSize.width, height: gridSize.height)
        titleLabel.frame = NSRect(x: pad, y: gridView.frame.maxY + spacing, width: gridSize.width, height: titleHeight)

        let multi = NSScreen.screens.count > 1
        var title = target?.appName ?? "No focused window"
        if multi { title += "  ·  \(screen.localizedName)" }
        titleLabel.stringValue = title

        var hints = ["Drag to resize", "Esc to close"]
        if multi { hints.insert("Tab: next display", at: 1) }
        hintLabel.stringValue = hints.joined(separator: "  ·  ")

        gridView.currentWindowUnit = target.flatMap(WindowManager.frame(of:)).map { Geometry.unit(for: $0, in: visible) }
        panel.invalidateShadow()
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

#if DEBUG
extension OverlayController {
    /// Debug builds: render the overlay without a target window (see `--snapshot`).
    func debugSnapshot() -> NSBitmapImageRep? {
        screen = NSScreen.main
        target = nil
        gridView.columns = store.config.columns
        gridView.rows = store.config.rows
        layout()
        gridView.currentWindowUnit = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        panel.orderFrontRegardless()
        gridView.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: gridView.convert(NSPoint(x: 5, y: 5), to: nil),
                                                     modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        gridView.mouseDragged(with: NSEvent.mouseEvent(with: .leftMouseDragged,
                                                        location: gridView.convert(NSPoint(x: gridView.bounds.midX - 5, y: gridView.bounds.midY - 5), to: nil),
                                                        modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}
#endif
