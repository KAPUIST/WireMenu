import XCTest
import AppKit
@testable import WireMenu

final class ConnectionKindTests: XCTestCase {
    func testMenuBarColorTracksAppearance() throws {
        let color = AppDelegate.menuBarSymbolColor
        for (name, expected) in [(NSAppearance.Name.aqua, CGFloat(0)), (.darkAqua, CGFloat(1))] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let resolved = color.usingColorSpace(.sRGB)!
                XCTAssertEqual(resolved.redComponent, expected, accuracy: 0.01)
                XCTAssertEqual(resolved.greenComponent, expected, accuracy: 0.01)
                XCTAssertEqual(resolved.blueComponent, expected, accuracy: 0.01)
                XCTAssertEqual(resolved.alphaComponent, 0.95, accuracy: 0.01)
            }
        }
    }

    func testMenuStaysInsideSecondaryDisplay() {
        let visible = NSRect(x: 1920, y: 0, width: 1920, height: 1080)
        let anchor = NSRect(x: 1920, y: 1050, width: 24, height: 30)
        let frame = MenuPanelLayout.frame(anchor: anchor, visibleFrame: visible, contentHeight: 2000)
        XCTAssertEqual(frame.height, 1042)
        XCTAssertEqual(frame.minX, visible.minX + 8)
        XCTAssertEqual(frame.minY, visible.minY + 8)
        XCTAssertEqual(frame.maxY, anchor.minY)
        XCTAssertEqual(MenuPanelLayout.frame(anchor: anchor, visibleFrame: visible, contentHeight: 400).height, 400)
    }

    func testMenuHandlesNegativeDisplayCoordinates() {
        let visible = NSRect(x: -1920, y: -1080, width: 1920, height: 1050)
        let anchor = NSRect(x: -24, y: -30, width: 24, height: 30)
        let frame = MenuPanelLayout.frame(anchor: anchor, visibleFrame: visible, contentHeight: 400)
        XCTAssertEqual(frame.maxX, -8)
        XCTAssertEqual(frame.maxY, -30)
        XCTAssertTrue(visible.contains(frame))
    }

    func testMenuKeyboardNavigation() {
        let rows = ["wifi", "hotspot", "settings"]
        XCTAssertEqual(MenuNavigation.next(current: nil, rows: rows, forward: true), "wifi")
        XCTAssertEqual(MenuNavigation.next(current: "wifi", rows: rows, forward: true), "hotspot")
        XCTAssertEqual(MenuNavigation.next(current: "wifi", rows: rows, forward: false), "settings")
        XCTAssertEqual(MenuNavigation.next(current: "removed", rows: rows, forward: false), "settings")
        XCTAssertNil(MenuNavigation.next(current: nil, rows: [], forward: true))
    }

    func testSharedEthernetSymbol() {
        XCTAssertEqual(ConnectionKind.ethernet.systemSymbolName, "display")
        XCTAssertEqual(ConnectionKind.hotspot.systemSymbolName, "personalhotspot")
    }

    func testConnectionPriorityAndHotspotDetection() {
        XCTAssertEqual(classify(satisfied: false), .offline)
        XCTAssertEqual(classify(wired: true, wifi: true), .ethernet)
        XCTAssertEqual(classify(wifi: true), .wifi)
        XCTAssertEqual(classify(wifi: true, expensive: true), .hotspot)
        XCTAssertEqual(classify(cellular: true), .hotspot)
        XCTAssertEqual(classify(), .other)
    }

    func testTrafficRateCalculationAndCounterReset() {
        XCTAssertEqual(TrafficRate.calculate(previous: 1_000, current: 3_000, seconds: 2), 1_000)
        XCTAssertEqual(TrafficRate.calculate(previous: 3_000, current: 1_000, seconds: 1), 0)
        XCTAssertEqual(TrafficRate.calculate(previous: 1_000, current: 3_000, seconds: 0), 0)
    }

    func testWiFiSignalStrengthLevels() {
        XCTAssertEqual(WiFiSignal.strength(for: -45), 1)
        XCTAssertEqual(WiFiSignal.strength(for: -62), 1)
        XCTAssertEqual(WiFiSignal.strength(for: -65), 1)
        XCTAssertEqual(WiFiSignal.strength(for: -66), 2.0 / 3.0)
        XCTAssertEqual(WiFiSignal.strength(for: -72), 2.0 / 3.0)
        XCTAssertEqual(WiFiSignal.strength(for: -75), 2.0 / 3.0)
        XCTAssertEqual(WiFiSignal.strength(for: -76), 1.0 / 3.0)
        XCTAssertEqual(WiFiSignal.strength(for: -85), 1.0 / 3.0)
        XCTAssertEqual(WiFiSignal.strength(for: 0), 0)
    }

    private func classify(
        satisfied: Bool = true,
        wired: Bool = false,
        wifi: Bool = false,
        cellular: Bool = false,
        expensive: Bool = false
    ) -> ConnectionKind {
        .classify(
            isSatisfied: satisfied,
            usesEthernet: wired,
            usesWiFi: wifi,
            usesCellular: cellular,
            isExpensive: expensive
        )
    }
}
