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

    /// The zones ICU names that Foundation does not list are given as their offset: Windows' "UTC" is `Etc/UTC`, which
    /// Foundation traps on as its default (GitHub's runners, M7 test round 1); a listed zone, or an alias that keeps
    /// daylight time, is itself.
    func testZonesFoundationDoesNotListAreTheirOffset() {
        for (identifier, offset) in [("Etc/UTC", 0), ("Etc/UCT", 0), ("Etc/Universal", 0), ("Etc/Zulu", 0), ("Etc/GMT+11", -11 * 3600)] {
            let zone = WindowsTimeZone.adoptable(identifier)
            XCTAssertEqual(zone?.secondsFromGMT(), offset, identifier)
            XCTAssertTrue(zone.map { TimeZone.knownTimeZoneIdentifiers.contains($0.identifier) || $0.identifier.hasPrefix("GMT") } ?? false, identifier)
        }
        XCTAssertEqual(WindowsTimeZone.adoptable("America/New_York")?.identifier, "America/New_York")
        XCTAssertEqual(WindowsTimeZone.adoptable("America/Indianapolis")?.identifier, "America/Indianapolis")
        XCTAssertNil(WindowsTimeZone.adoptable("No/Such_Zone"))
    }

    /// Windows' "UTC" adopted as Foundation's default: it is GMT, and Foundation goes on.
    func testTheUTCZoneCanBeTheDefault() throws {
        let before = NSTimeZone.default
        defer { NSTimeZone.default = before }
        let identifier = try XCTUnwrap(WindowsTimeZone.ianaIdentifier(forWindows: "UTC"))
        NSTimeZone.default = try XCTUnwrap(WindowsTimeZone.adoptable(identifier))
        XCTAssertEqual(Calendar.current.timeZone.secondsFromGMT(for: Date()), 0)
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
