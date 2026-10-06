import Testing
import Foundation
import Carbon.HIToolbox
@testable import GridCore

@Suite struct GeometryTests {
    let visible = CGRect(x: 0, y: 70, width: 1512, height: 875) // laptop-ish, dock at bottom

    @Test func fullScreenUnitFillsVisibleFrame() {
        #expect(Geometry.frame(forUnit: CGRect(x: 0, y: 0, width: 1, height: 1), in: visible) == visible)
    }

    @Test func upperLeftQuarterOf4x4() {
        let unit = GridRect(x: 0, y: 0, w: 2, h: 2).unitRect(columns: 4, rows: 4)
        let f = Geometry.frame(forUnit: unit, in: visible)
        #expect(f.minX == 0)
        #expect(f.maxY == visible.maxY) // top edge
        #expect(f.width == 756)
        #expect(f.minY == (visible.maxY - 875.0 / 2).rounded()) // bottom edge rounded independently
    }

    @Test func adjacentCellsShareEdges() {
        // 7 columns doesn't divide evenly; edges must still line up exactly.
        for col in 0..<6 {
            let a = Geometry.frame(forUnit: GridRect(x: col, y: 0, w: 1, h: 1).unitRect(columns: 7, rows: 3), in: visible)
            let b = Geometry.frame(forUnit: GridRect(x: col + 1, y: 0, w: 1, h: 1).unitRect(columns: 7, rows: 3), in: visible)
            #expect(a.maxX == b.minX)
        }
    }

    @Test func flipRoundTrips() {
        let r = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = Geometry.flip(r, primaryHeight: 982)
        #expect(ax.minY == CGFloat(382))
        #expect(Geometry.flip(ax, primaryHeight: 982) == r)
    }

    @Test func unitIsInverseOfFrame() {
        let unit = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let f = Geometry.frame(forUnit: unit, in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(Geometry.unit(for: f, in: CGRect(x: 0, y: 0, width: 1000, height: 800)) == unit)
    }

    @Test func relocateKeepsProportionsAcrossScreens() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: -200, width: 2000, height: 1200)
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800)
        #expect(Geometry.relocate(leftHalf, from: left, to: right) == CGRect(x: 1000, y: -200, width: 1000, height: 1200))
    }

    @Test func relocateClampsOversizedWindows() {
        let src = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let dst = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let tooBig = CGRect(x: -50, y: -50, width: 1200, height: 1000)
        let r = Geometry.relocate(tooBig, from: src, to: dst)
        #expect(dst.contains(r))
    }

    @Test func bestScreenPicksLargestOverlap() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        #expect(Geometry.bestScreenIndex(for: CGRect(x: 900, y: 0, width: 400, height: 400), screens: screens) == 1)
        #expect(Geometry.bestScreenIndex(for: CGRect(x: 5000, y: 0, width: 10, height: 10), screens: screens) == 1)
    }
}

@Suite struct ModelTests {
    @Test func spanningIsOrderIndependent() {
        let a = GridCell(col: 3, row: 0), b = GridCell(col: 1, row: 2)
        #expect(GridRect.spanning(a, b) == GridRect(x: 1, y: 0, w: 3, h: 3))
        #expect(GridRect.spanning(b, a) == GridRect(x: 1, y: 0, w: 3, h: 3))
    }

    @Test func clampKeepsRectInsideSmallerGrid() {
        #expect(GridRect(x: 3, y: 3, w: 4, h: 4).clamped(columns: 2, rows: 2) == GridRect(x: 1, y: 1, w: 1, h: 1))
    }

    @Test func plainKeyAndCommandKeyAreDifferentCombos() {
        let c = KeyCombo(keyCode: UInt16(kVK_ANSI_C))
        let cmdC = KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifiers: .command)
        #expect(c != cmdC)
        #expect(c.carbonModifiers == 0)
    }

    @Test func irrelevantModifierFlagsAreIgnored() {
        // Arrow keys carry .function/.numericPad; caps lock shouldn't matter either.
        let a = KeyCombo(keyCode: UInt16(kVK_LeftArrow), modifiers: [.function, .numericPad, .capsLock])
        #expect(a == KeyCombo(keyCode: UInt16(kVK_LeftArrow)))
    }

    @Test func configRoundTripsAndToleratesMissingKeys() throws {
        var config = Config()
        config.columns = 7
        config.repeatBehavior = .closeOverlay
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)

        let partial = try JSONDecoder().decode(Config.self, from: Data(#"{"columns": 99}"#.utf8))
        #expect(partial.columns == 10)
        #expect(partial.rows == 4)
        #expect(partial.launchKey == .defaultLaunch)
    }

    @Test func defaultShortcutKeysAreUnique() {
        let keys = Config.defaultShortcuts.compactMap(\.key)
        #expect(Set(keys).count == keys.count)
    }
}
