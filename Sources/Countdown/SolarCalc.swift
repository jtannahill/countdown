import Foundation

/// Pure sunset computation via the Almanac-for-Computers / NOAA sunrise-sunset
/// algorithm. Accurate to ~1-2 minutes; no network, no entitlement.
enum SolarCalc {
    /// Sunset instant for the local day of `date` at the given coordinates, or
    /// nil for polar days with no sunset. `longitude` is East-positive.
    static func sunset(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> Date? {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = timeZone
        let comps = localCal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        guard let dayDate = utcCal.date(from: DateComponents(year: year, month: month, day: day)),
              let dayOfYear = utcCal.ordinality(of: .day, in: .year, for: dayDate) else { return nil }

        let D2R = Double.pi / 180, R2D = 180 / Double.pi
        let zenith = 90.833   // official sunset (accounts for refraction + solar radius)

        let lngHour = longitude / 15.0
        let t = Double(dayOfYear) + ((18.0 - lngHour) / 24.0)   // 18 = sunset approximation

        let M = (0.9856 * t) - 3.289                            // sun mean anomaly
        var L = M + (1.916 * sin(M * D2R)) + (0.020 * sin(2 * M * D2R)) + 282.634
        L = mod(L, 360)                                         // sun true longitude

        var RA = R2D * atan(0.91764 * tan(L * D2R))             // right ascension
        RA = mod(RA, 360)
        RA += (floor(L / 90) * 90) - (floor(RA / 90) * 90)      // same quadrant as L
        RA /= 15

        let sinDec = 0.39782 * sin(L * D2R)
        let cosDec = cos(asin(sinDec))

        let cosH = (cos(zenith * D2R) - (sinDec * sin(latitude * D2R))) / (cosDec * cos(latitude * D2R))
        if cosH > 1 || cosH < -1 { return nil }                 // no sunset: polar night or midnight sun

        var H = R2D * acos(cosH)                                // sunset hour angle
        H /= 15
        let localT = H + RA - (0.06571 * t) - 6.622
        let ut = mod(localT - lngHour, 24)                      // UTC hours

        let hour = Int(ut)
        let minF = (ut - Double(hour)) * 60
        let minute = Int(minF)
        let second = Int((minF - Double(minute)) * 60)
        return utcCal.date(from: DateComponents(year: year, month: month, day: day,
                                                hour: hour, minute: minute, second: second))
    }

    /// Today's sunset if still ahead of `now`, otherwise tomorrow's. nil if neither exists.
    static func nextSunset(after now: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> Date? {
        if let today = sunset(on: now, latitude: latitude, longitude: longitude, timeZone: timeZone), today > now {
            return today
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
        return sunset(on: tomorrow, latitude: latitude, longitude: longitude, timeZone: timeZone)
    }

    private static func mod(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
}
