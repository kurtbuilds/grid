import Foundation
import Carbon.HIToolbox

public struct GridCell: Hashable, Sendable {
    public var col: Int
    public var row: Int
    public init(col: Int, row: Int) { self.col = col; self.row = row }
}

/// A rectangle of grid cells. `y` counts rows from the top.
public struct GridRect: Codable, Hashable, Sendable {
    public var x: Int, y: Int, w: Int, h: Int

    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }

    public static func spanning(_ a: GridCell, _ b: GridCell) -> GridRect {
        GridRect(x: min(a.col, b.col), y: min(a.row, b.row),
                 w: abs(a.col - b.col) + 1, h: abs(a.row - b.row) + 1)
    }

    public func contains(col: Int, row: Int) -> Bool {
        col >= x && col < x + w && row >= y && row < y + h
    }

    /// Fraction of the screen this covers, origin top-left.
    public func unitRect(columns: Int, rows: Int) -> CGRect {
        let c = Double(max(columns, 1)), r = Double(max(rows, 1))
        return CGRect(x: Double(x) / c, y: Double(y) / r, width: Double(w) / c, height: Double(h) / r)
    }

    /// Keeps the rect inside a grid of the given size.
    public func clamped(columns: Int, rows: Int) -> GridRect {
        let nx = min(max(x, 0), columns - 1), ny = min(max(y, 0), rows - 1)
        return GridRect(x: nx, y: ny, w: min(max(w, 1), columns - nx), h: min(max(h, 1), rows - ny))
    }
}

/// A saved grid selection triggered by a single key while the overlay is open.
/// It remembers the grid it was drawn on, so changing the main grid size never breaks it.
public struct GridShortcut: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var key: KeyCombo?
    public var columns: Int
    public var rows: Int
    public var rect: GridRect

    public init(id: UUID = UUID(), name: String, key: KeyCombo?, columns: Int, rows: Int, rect: GridRect) {
        self.id = id; self.name = name; self.key = key
        self.columns = columns; self.rows = rows; self.rect = rect
    }

    public var unitRect: CGRect { rect.unitRect(columns: columns, rows: rows) }
}

public enum RepeatBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case cycleDisplays, closeOverlay
    public var id: Self { self }
    public var title: String {
        switch self {
        case .cycleDisplays: "Moves window to the next display"
        case .closeOverlay: "Closes the grid"
        }
    }
}

public struct Config: Codable, Equatable, Sendable {
    public static let gridRange = 1...10

    public var launchKey: KeyCombo = .defaultLaunch
    public var columns = 4
    public var rows = 4
    public var repeatBehavior: RepeatBehavior = .cycleDisplays
    public var showPreview = true
    public var shortcuts: [GridShortcut] = Config.defaultShortcuts

    public init() {}

    // Tolerant decoding: missing keys (from older versions) fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        launchKey = try c.decodeIfPresent(KeyCombo.self, forKey: .launchKey) ?? d.launchKey
        columns = (try c.decodeIfPresent(Int.self, forKey: .columns) ?? d.columns).clamped(to: Self.gridRange)
        rows = (try c.decodeIfPresent(Int.self, forKey: .rows) ?? d.rows).clamped(to: Self.gridRange)
        repeatBehavior = (try? c.decodeIfPresent(RepeatBehavior.self, forKey: .repeatBehavior)) ?? d.repeatBehavior
        showPreview = try c.decodeIfPresent(Bool.self, forKey: .showPreview) ?? d.showPreview
        shortcuts = try c.decodeIfPresent([GridShortcut].self, forKey: .shortcuts) ?? d.shortcuts
    }

    public func shortcut(for combo: KeyCombo) -> GridShortcut? {
        shortcuts.first { $0.key == combo }
    }

    public static let defaultShortcuts: [GridShortcut] = [
        GridShortcut(name: "Full Screen", key: KeyCombo(keyCode: UInt16(kVK_ANSI_F)), columns: 4, rows: 4,
                     rect: GridRect(x: 0, y: 0, w: 4, h: 4)),
        GridShortcut(name: "Center", key: KeyCombo(keyCode: UInt16(kVK_ANSI_C)), columns: 4, rows: 4,
                     rect: GridRect(x: 1, y: 1, w: 2, h: 2)),
        GridShortcut(name: "Left Half", key: KeyCombo(keyCode: UInt16(kVK_LeftArrow)), columns: 4, rows: 4,
                     rect: GridRect(x: 0, y: 0, w: 2, h: 4)),
        GridShortcut(name: "Right Half", key: KeyCombo(keyCode: UInt16(kVK_RightArrow)), columns: 4, rows: 4,
                     rect: GridRect(x: 2, y: 0, w: 2, h: 4)),
        GridShortcut(name: "Top Half", key: KeyCombo(keyCode: UInt16(kVK_UpArrow)), columns: 4, rows: 4,
                     rect: GridRect(x: 0, y: 0, w: 4, h: 2)),
        GridShortcut(name: "Bottom Half", key: KeyCombo(keyCode: UInt16(kVK_DownArrow)), columns: 4, rows: 4,
                     rect: GridRect(x: 0, y: 2, w: 4, h: 2)),
        GridShortcut(name: "Upper Left", key: KeyCombo(keyCode: UInt16(kVK_ANSI_Q)), columns: 4, rows: 4,
                     rect: GridRect(x: 0, y: 0, w: 2, h: 2)),
        GridShortcut(name: "Upper Right", key: KeyCombo(keyCode: UInt16(kVK_ANSI_W)), columns: 4, rows: 4,
                     rect: GridRect(x: 2, y: 0, w: 2, h: 2)),
        GridShortcut(name: "Lower Left", key: KeyCombo(keyCode: UInt16(kVK_ANSI_A)), columns: 4, rows: 4,
                     rect: GridRect(x: 0, y: 2, w: 2, h: 2)),
        GridShortcut(name: "Lower Right", key: KeyCombo(keyCode: UInt16(kVK_ANSI_S)), columns: 4, rows: 4,
                     rect: GridRect(x: 2, y: 2, w: 2, h: 2)),
    ]
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
