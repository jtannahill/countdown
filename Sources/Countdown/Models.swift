import SwiftUI
import Foundation

extension Color {
    // Bloomberg Terminal default orange (#FE9624)
    static let bloombergOrange = Color(red: 0xFE / 255.0, green: 0x96 / 255.0, blue: 0x24 / 255.0)
    static let bloombergOrangeDim = Color(red: 0xFE / 255.0, green: 0x96 / 255.0, blue: 0x24 / 255.0).opacity(0.55)
    static let bloombergOrangeFaint = Color(red: 0xFE / 255.0, green: 0x96 / 255.0, blue: 0x24 / 255.0).opacity(0.35)
}

enum NHG {
    case regular, medium, bold
    var psName: String {
        switch self {
        case .regular: return "NeueHaasDisplay-Roman"
        case .medium:  return "NeueHaasDisplay-Mediu"
        case .bold:    return "NeueHaasDisplay-Bold"
        }
    }
}

extension Font {
    static func nhg(_ size: CGFloat, _ weight: NHG = .regular) -> Font {
        .custom(weight.psName, size: size)
    }
}

enum TerminalColor: String, Codable, CaseIterable, Identifiable {
    case orange, amber, cyan, green, red, white
    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .orange: return Color(red: 0xFE/255.0, green: 0x96/255.0, blue: 0x24/255.0)
        case .amber:  return Color(red: 0xFF/255.0, green: 0xB3/255.0, blue: 0x00/255.0)
        case .cyan:   return Color(red: 0x49/255.0, green: 0xD7/255.0, blue: 0xFF/255.0)
        case .green:  return Color(red: 0x6C/255.0, green: 0xFF/255.0, blue: 0x6C/255.0)
        case .red:    return Color(red: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4D/255.0)
        case .white:  return Color(red: 0xE5/255.0, green: 0xE5/255.0, blue: 0xE5/255.0)
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum CountdownMode: String, Codable, CaseIterable, Identifiable {
    case daily
    case fixed
    case nextEvent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily: return "Daily"
        case .fixed: return "Fixed date"
        case .nextEvent: return "Next event"
        }
    }
}

struct Countdown: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var label: String = "EOD"
    var mode: CountdownMode = .daily

    // Daily mode
    var resetHour: Int = 9
    var resetMinute: Int = 0
    var targetHour: Int = 17
    var targetMinute: Int = 30

    // Fixed mode
    var targetTimestamp: Double = Date().addingTimeInterval(86400 * 30).timeIntervalSince1970

    var color: TerminalColor = .orange

    // Notifications: minutes-before thresholds; 0 is handled separately by alertAtZero.
    var alertOffsets: [Int] = []
    var alertAtZero: Bool = false

    // Next-event mode: how far ahead an event counts as "imminent" before falling back to EOD.
    var eventLookaheadHours: Int = 12

    // Calendar write: identifier of the linked EKEvent (nil = not added) + its duration.
    var calendarEventID: String? = nil
    var eventDurationMinutes: Int = 60

    init(label: String = "EOD") {
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id, label, mode, resetHour, resetMinute, targetHour, targetMinute, targetTimestamp, color
        case alertOffsets, alertAtZero, eventLookaheadHours
        case calendarEventID, eventDurationMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "EOD"
        mode = try c.decodeIfPresent(CountdownMode.self, forKey: .mode) ?? .daily
        resetHour = try c.decodeIfPresent(Int.self, forKey: .resetHour) ?? 9
        resetMinute = try c.decodeIfPresent(Int.self, forKey: .resetMinute) ?? 0
        targetHour = try c.decodeIfPresent(Int.self, forKey: .targetHour) ?? 17
        targetMinute = try c.decodeIfPresent(Int.self, forKey: .targetMinute) ?? 30
        targetTimestamp = try c.decodeIfPresent(Double.self, forKey: .targetTimestamp) ?? Date().addingTimeInterval(86400 * 30).timeIntervalSince1970
        color = try c.decodeIfPresent(TerminalColor.self, forKey: .color) ?? .orange
        alertOffsets = try c.decodeIfPresent([Int].self, forKey: .alertOffsets) ?? []
        alertAtZero = try c.decodeIfPresent(Bool.self, forKey: .alertAtZero) ?? false
        eventLookaheadHours = try c.decodeIfPresent(Int.self, forKey: .eventLookaheadHours) ?? 12
        calendarEventID = try c.decodeIfPresent(String.self, forKey: .calendarEventID)
        eventDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .eventDurationMinutes) ?? 60
    }

    func currentTarget(now: Date = Date()) -> Date {
        switch mode {
        case .fixed:
            return Date(timeIntervalSince1970: targetTimestamp)
        case .daily, .nextEvent:
            // .nextEvent uses this only as its EOD fallback; the live event
            // target is resolved by CountdownTarget (see Task 2 onward).
            let cal = Calendar.current
            var anchorComps = cal.dateComponents([.year, .month, .day], from: now)
            anchorComps.hour = resetHour
            anchorComps.minute = resetMinute
            anchorComps.second = 0
            let todayReset = cal.date(from: anchorComps) ?? now
            let anchor = todayReset <= now ? todayReset : (cal.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset)
            var targetComps = cal.dateComponents([.year, .month, .day], from: anchor)
            targetComps.hour = targetHour
            targetComps.minute = targetMinute
            targetComps.second = 0
            return cal.date(from: targetComps) ?? now
        }
    }

    var subtitle: String {
        switch mode {
        case .daily:
            return "daily · \(formatHM(resetHour, resetMinute)) → \(formatHM(targetHour, targetMinute))"
        case .fixed:
            let date = Date(timeIntervalSince1970: targetTimestamp)
            let f = DateFormatter()
            f.dateFormat = "EEE MMM d · h:mm a"
            return f.string(from: date).lowercased()
        case .nextEvent:
            return "next event · fallback EOD \(formatHM(targetHour, targetMinute))"
        }
    }
}

private func formatHM(_ h: Int, _ m: Int) -> String {
    let period = h >= 12 ? "pm" : "am"
    var hour12 = h % 12
    if hour12 == 0 { hour12 = 12 }
    return String(format: "%d:%02d %@", hour12, m, period)
}

final class CountdownStore: ObservableObject {
    static let shared = CountdownStore()

    @Published var items: [Countdown] = [] {
        didSet { save() }
    }

    private let key = "countdowns.v2"
    private var suppressSave = false

    private init() {
        suppressSave = true
        load()
        if items.isEmpty {
            items = [Countdown(label: "EOD")]
        }
        suppressSave = false
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Countdown].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if suppressSave { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add() {
        items.append(Countdown(label: "New"))
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }
}

// Date helper for hour-minute pickers
enum Pasteboard {
    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

extension Countdown {
    static func formatRemaining(_ r: (d: Int, h: Int, m: Int, s: Int, expired: Bool), mode: CountdownMode) -> String {
        if r.expired { return mode == .daily ? "WAITING" : "00:00:00" }
        if r.d > 0 {
            return String(format: "%dd %02d:%02d:%02d", r.d, r.h, r.m, r.s)
        }
        return String(format: "%02d:%02d:%02d", r.h, r.m, r.s)
    }

    func absoluteTargetString(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, h:mm a"
        return f.string(from: currentTarget(now: now))
    }
}

extension Calendar {
    func dateFromHM(_ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.hour = hour
        c.minute = minute
        return self.date(from: c) ?? Date()
    }
}

struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hudMode: Bool {
        didSet {
            UserDefaults.standard.set(hudMode, forKey: "hudMode")
            WindowSizer.shared.applySize()
        }
    }

    @Published var menuBarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(menuBarEnabled, forKey: "menuBarEnabled")
            MenuBarController.shared.refresh()
        }
    }

    private init() {
        hudMode = UserDefaults.standard.bool(forKey: "hudMode")
        menuBarEnabled = UserDefaults.standard.bool(forKey: "menuBarEnabled")
    }
}

final class WindowSizer: ObservableObject {
    static let shared = WindowSizer()
    weak var window: NSWindow?

    /// When a saved window frame was restored on launch, keep it pinned:
    /// track the natural content height for scaling math but never auto-resize
    /// the window from content layout. Explicit user actions still resize.
    var honorSavedFrame = false

    var baseWidth: CGFloat {
        AppSettings.shared.hudMode ? 380 : 520
    }
    private(set) var naturalContentHeight: CGFloat = 220

    private var scaleKey: String {
        AppSettings.shared.hudMode ? "userScale.hud" : "userScale.full"
    }

    var userScale: CGFloat {
        let s = UserDefaults.standard.double(forKey: scaleKey)
        return s > 0 ? CGFloat(s) : 1.0
    }

    func updateNaturalContentHeight(_ h: CGFloat) {
        guard h > 1, abs(h - naturalContentHeight) > 0.5 else { return }
        naturalContentHeight = h
        // Pinned to a restored frame: record height for scale math, but don't
        // override the user's saved position/size on launch.
        if honorSavedFrame { return }
        applySize()
    }

    func setUserScale(_ scale: CGFloat) {
        let clamped = max(0.4, min(3.0, scale))
        UserDefaults.standard.set(Double(clamped), forKey: scaleKey)
        applySize()
    }

    func applySize() {
        guard let w = window else { return }
        let scale = userScale
        let newWidth = baseWidth * scale
        let newHeight = naturalContentHeight * scale
        let frame = w.frame
        if abs(newWidth - frame.size.width) < 0.5 && abs(newHeight - frame.size.height) < 0.5 {
            return
        }
        let newOriginY = frame.origin.y + frame.size.height - newHeight
        let newFrame = NSRect(x: frame.origin.x, y: newOriginY, width: newWidth, height: newHeight)
        w.setFrame(newFrame, display: true, animate: false)
    }
}
