import CoreGraphics

/// Pure geometry helpers. Two coordinate systems are involved:
/// - AppKit (NSScreen): origin at bottom-left of the primary display, y up.
/// - Accessibility (AX):  origin at top-left of the primary display, y down.
public enum Geometry {
    /// Converts between AppKit and AX coordinates (the transform is its own inverse).
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Frame (AppKit coords) for a unit rect (origin top-left, 0...1) inside a screen's visible frame.
    /// Edges are rounded independently so adjacent cells share an exact edge with no gaps or overlaps.
    public static func frame(forUnit unit: CGRect, in visible: CGRect) -> CGRect {
        let left = (visible.minX + visible.width * unit.minX).rounded()
        let right = (visible.minX + visible.width * unit.maxX).rounded()
        let top = (visible.maxY - visible.height * unit.minY).rounded()
        let bottom = (visible.maxY - visible.height * unit.maxY).rounded()
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// Unit rect (origin top-left) describing where `frame` sits inside `visible`.
    public static func unit(for frame: CGRect, in visible: CGRect) -> CGRect {
        guard visible.width > 0, visible.height > 0 else { return .zero }
        return CGRect(x: (frame.minX - visible.minX) / visible.width,
                      y: (visible.maxY - frame.maxY) / visible.height,
                      width: frame.width / visible.width,
                      height: frame.height / visible.height)
    }

    /// Moves a frame to another screen, keeping its proportional position and size,
    /// then clamps it so it is fully on the destination screen.
    public static func relocate(_ frame: CGRect, from source: CGRect, to dest: CGRect) -> CGRect {
        let u = unit(for: frame, in: source)
        var r = Geometry.frame(forUnit: u, in: dest)
        r.size.width = min(r.width, dest.width)
        r.size.height = min(r.height, dest.height)
        r.origin.x = min(max(r.minX, dest.minX), dest.maxX - r.width)
        r.origin.y = min(max(r.minY, dest.minY), dest.maxY - r.height)
        return r
    }

    /// Index of the rect with the largest overlap with `frame`, falling back to the nearest center.
    public static func bestScreenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let areas = screens.map { s -> CGFloat in
            let i = s.intersection(frame)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        let c = CGPoint(x: frame.midX, y: frame.midY)
        return screens.indices.min { a, b in
            hypot(screens[a].midX - c.x, screens[a].midY - c.y) < hypot(screens[b].midX - c.x, screens[b].midY - c.y)
        }
    }
}
