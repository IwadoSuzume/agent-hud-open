#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// Windows' time zone for Foundation (Platform/Windows/WindowsTimeZone.swift): swift-corelibs-foundation reports GMT on
/// Windows, so the engine adopts Windows' own zone as Foundation's default.
final class WindowsTimeZoneTests: XCTestCase {
    func testWindowsZoneNamesMapToTheirIANAIdentifiers() {
        XCTAssertEqual(WindowsTimeZone.ianaIdentifier(forWindows: "Eastern Standard Time"), "America/New_York")
        XCTAssertEqual(WindowsTimeZone.ianaIdentifier(forWindows: "China Standard Time"), "Asia/Shanghai")
        XCTAssertNotNil(WindowsTimeZone.ianaIdentifier(forWindows: "UTC"))
        XCTAssertNil(WindowsTimeZone.ianaIdentifier(forWindows: "No Such Standard Time"))
        XCTAssertNil(WindowsTimeZone.ianaIdentifier(forWindows: ""))
    }

    /// The zone is Windows' own: its offset now is the offset Windows applies now.
    func testTheZoneHasWindowsCurrentOffset() {
        var info = TIME_ZONE_INFORMATION()
        let kind = GetTimeZoneInformation(&info)
        let bias = Int(info.Bias) + (kind == DWORD(TIME_ZONE_ID_DAYLIGHT) ? Int(info.DaylightBias) : Int(info.StandardBias))
        XCTAssertEqual(WindowsTimeZone.current().secondsFromGMT(for: Date()), -bias * 60)
    }

    /// Adopted, it is what Calendar.current and a DateFormatter use.
    func testAdoptingItMakesItFoundationsDefault() {
        let before = NSTimeZone.default
        defer { NSTimeZone.default = before }
        WindowsTimeZone.adopt()
        XCTAssertEqual(Calendar.current.timeZone.secondsFromGMT(for: Date()), WindowsTimeZone.current().secondsFromGMT(for: Date()))
        XCTAssertEqual(DateFormatter().timeZone.secondsFromGMT(for: Date()), WindowsTimeZone.current().secondsFromGMT(for: Date()))
    }
}
#endif
