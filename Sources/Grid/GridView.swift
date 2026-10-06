import AppKit
import GridCore

/// The interactive grid inside the overlay. Hover highlights a cell; click-drag selects a block.
final class GridView: NSView {
    var columns = 4 { didSet { reset() } }
    var rows = 4 { didSet { reset() } }
    /// Where the target window currently sits (unit rect, origin top-left), drawn as a dashed outline.
    var currentWindowUnit: CGRect? { didSet { needsDisplay = true } }

    var onHighlight: ((GridRect?) -> Void)?
    var onSelect: ((GridRect) -> Void)?

    private var dragStart: GridCell?
    private var dragCurrent: GridCell?
    private var hoverCell: GridCell?
    private var trackingArea: NSTrackingArea?
    private let gap: CGFloat = 4

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var highlighted: GridRect? {
        if let s = dragStart, let c = dragCurrent { return .spanning(s, c) }
        if let h = hoverCell { return .spanning(h, h) }
        return nil
    }

    func reset() {
        dragStart = nil
        dragCurrent = nil
        hoverCell = nil
        needsDisplay = true
    }

    private func cell(at point: NSPoint) -> GridCell {
        let col = Int(point.x / bounds.width * CGFloat(columns))
        let row = Int(point.y / bounds.height * CGFloat(rows))
        return GridCell(col: min(max(col, 0), columns - 1), row: min(max(row, 0), rows - 1))
    }

    private func cellRect(col: Int, row: Int) -> NSRect {
        let w = bounds.width / CGFloat(columns), h = bounds.height / CGFloat(rows)
        return NSRect(x: CGFloat(col) * w, y: CGFloat(row) * h, width: w, height: h).insetBy(dx: gap / 2, dy: gap / 2)
    }

    private func notify() {
        needsDisplay = true
        onHighlight?(highlighted)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // .activeAlways: our app is never the active app while the overlay is up.
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard dragStart == nil else { return }
        let c = cell(at: convert(event.locationInWindow, from: nil))
        if c != hoverCell { hoverCell = c; notify() }
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStart == nil else { return }
        hoverCell = nil
        notify()
    }

    override func mouseDown(with event: NSEvent) {
        let c = cell(at: convert(event.locationInWindow, from: nil))
        dragStart = c
        dragCurrent = c
        notify()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        let c = cell(at: convert(event.locationInWindow, from: nil))
        if c != dragCurrent { dragCurrent = c; notify() }
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = dragStart, let c = dragCurrent else { return }
        let rect = GridRect.spanning(s, c)
        reset()
        onSelect?(rect)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let selection = highlighted
        for row in 0..<rows {
            for col in 0..<columns {
                let r = cellRect(col: col, row: row)
                let selected = selection?.contains(col: col, row: row) ?? false
                let color: NSColor = selected
                    ? accent.withAlphaComponent(dragStart != nil ? 0.9 : 0.55)
                    : NSColor.labelColor.withAlphaComponent(0.10)
                color.setFill()
                NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            }
        }

        if let u = currentWindowUnit {
            let r = NSRect(x: u.minX * bounds.width, y: u.minY * bounds.height,
                           width: u.width * bounds.width, height: u.height * bounds.height)
                .intersection(bounds).insetBy(dx: 1, dy: 1)
            if !r.isEmpty {
                let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                path.lineWidth = 1.5
                path.setLineDash([5, 4], count: 2, phase: 0)
                NSColor.labelColor.withAlphaComponent(0.45).setStroke()
                path.stroke()
            }
        }
    }
}
