#if os(Windows)
import Foundation
import WinSDK

/// The user's time zone for Foundation on Windows, where swift-corelibs-foundation reports GMT whatever Windows says
/// (measured, PROGRESS known issues): Windows' zone name ("Eastern Standard Time") mapped to its IANA identifier by the
/// system's ICU (`icu.dll`, Windows 10 1903 and later; Foundation's own ICU does not export the mapping), else a zone at
/// Windows' current offset. `adopt()` makes it Foundation's default, which `Calendar.current` and `DateFormatter` take, so
/// Core's weekday-and-time labels read as the clock on the wall.
enum WindowsTimeZone {
    /// `ucal_getTimeZoneIDForWindowsID(winid, len, region, id, capacity, status)`.
    private typealias Mapper = @convention(c) (UnsafePointer<UInt16>?, Int32, UnsafePointer<CChar>?,
                                               UnsafeMutablePointer<UInt16>?, Int32, UnsafeMutablePointer<Int32>?) -> Int32

    static func adopt() {
        NSTimeZone.default = current()
    }

    static func current() -> TimeZone {
        var info = DYNAMIC_TIME_ZONE_INFORMATION()
        let kind = GetDynamicTimeZoneInformation(&info)
        let key = withUnsafeBytes(of: info.TimeZoneKeyName) { raw in
            String(decoding: raw.bindMemory(to: UInt16.self).prefix { $0 != 0 }, as: UTF16.self)
        }
        if let identifier = ianaIdentifier(forWindows: key), let zone = TimeZone(identifier: identifier) { return zone }
        // UTC = local + bias, in minutes; the daylight bias applies while daylight time is in force.
        let bias = Int(info.Bias) + (kind == DWORD(TIME_ZONE_ID_DAYLIGHT) ? Int(info.DaylightBias) : Int(info.StandardBias))
        return TimeZone(secondsFromGMT: -bias * 60) ?? TimeZone(secondsFromGMT: 0)!
    }

    /// The IANA identifier of a Windows zone name, or nil without the system's ICU or for a name it does not know.
    static func ianaIdentifier(forWindows key: String) -> String? {
        guard !key.isEmpty,
              let icu = Win32.withWide("icu.dll", { LoadLibraryExW($0, nil, DWORD(LOAD_LIBRARY_SEARCH_SYSTEM32)) }),
              let address = GetProcAddress(icu, "ucal_getTimeZoneIDForWindowsID") else { return nil }
        let map = unsafeBitCast(address, to: Mapper.self)
        let name = Array(key.utf16)
        var identifier = [UInt16](repeating: 0, count: 128)
        var status: Int32 = 0
        let count = name.withUnsafeBufferPointer { name in
            identifier.withUnsafeMutableBufferPointer { out in
                map(name.baseAddress, Int32(name.count), nil, out.baseAddress, Int32(out.count), &status)
            }
        }
        // ICU's U_ZERO_ERROR is 0; warnings are negative, failures positive.
        guard status <= 0, count > 0, count < identifier.count else { return nil }
        return String(decoding: identifier.prefix(Int(count)), as: UTF16.self)
    }
}
#endif
