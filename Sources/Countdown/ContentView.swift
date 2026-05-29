import SwiftUI
import AppKit

/// "90" → "1h 30m", "45" → "45m", "120" → "2h". Shared by the calendar controls
/// and the New event form.
fileprivate func durationLabel(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m)m" }
    if m == 0 { return "\(h)h" }
    return "\(h)h \(m)m"
}

struct ContentView: View {
    @StateObject private var store = CountdownStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var eventService = EventKitService.shared
    @State private var now = Date()
    @State private var isHovering = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let baseWidth: CGFloat = settings.hudMode ? 380 : 520
            let scale = max(0.4, geo.size.width / baseWidth)
            ZStack(alignment: .topLeading) {
                Color.black

                ZStack(alignment: .topTrailing) {
                    Group {
                        if settings.hudMode {
                            HUDView(store: store, now: now, isHovering: isHovering)
                        } else {
                            fullStack
                                .opacity(isHovering ? 0.18 : 1.0)
                                .animation(.easeOut(duration: 0.15), value: isHovering)
                        }
                    }
                    .frame(width: baseWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { gp in
                            Color.clear.preference(key: ContentSizeKey.self, value: gp.size)
                        }
                    )

                    if isHovering {
                        HStack(spacing: 6) {
                            iconButton("plus") {
                                store.add()
                                if settings.hudMode { settings.hudMode = false }
                                SettingsWindowController.shared.show()
                            }
                            iconButton(settings.hudMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical") {
                                settings.hudMode.toggle()
                            }
                            iconButton("gearshape.fill") { SettingsWindowController.shared.show() }
                            iconButton("xmark") { NSApp.terminate(nil) }
                        }
                        .padding(10)
                        .transition(.opacity)
                    }
                }
                .frame(width: baseWidth, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
            }
        }
        .background(Color.black)
        .onReceive(timer) { now = $0 }
        .onPreferenceChange(ContentSizeKey.self) { size in
            WindowSizer.shared.updateNaturalContentHeight(size.height)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    private var fullStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.items.isEmpty {
                Text("NO COUNTDOWNS")
                    .font(.nhg(13, .medium))
                    .foregroundColor(.bloombergOrangeDim)
                    .tracking(2)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    CountdownRow(item: item, now: now, nextEvent: eventService.nextEvent)
                    if index < store.items.count - 1 {
                        Rectangle()
                            .fill(Color.bloombergOrange.opacity(0.12))
                            .frame(height: 1)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .padding(22)
    }

    private func iconButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.bloombergOrange.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.bloombergOrange.opacity(0.12))
                        .overlay(Circle().strokeBorder(Color.bloombergOrange.opacity(0.25), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }
}

struct CountdownRow: View {
    let item: Countdown
    let now: Date
    var nextEvent: EventInfo?
    @State private var justCopied = false

    private var accent: Color { item.color.swiftUIColor }
    private var accentDim: Color { item.color.swiftUIColor.opacity(0.55) }
    private var accentFaint: Color { item.color.swiftUIColor.opacity(0.35) }

    private var timeString: String { Countdown.formatRemaining(remaining, mode: item.mode) }

    private func copy(_ s: String) {
        Pasteboard.copy(s)
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
        }
    }

    private var resolved: ResolvedTarget {
        CountdownTarget.resolve(item, now: now,
                                nextEventStart: nextEvent?.startDate,
                                nextEventTitle: nextEvent?.title)
    }
    private var target: Date { resolved.date }
    private var displayLabel: String { resolved.title ?? item.label }

    private var remaining: (d: Int, h: Int, m: Int, s: Int, expired: Bool) {
        let interval = target.timeIntervalSince(now)
        if interval <= 0 { return (0, 0, 0, 0, true) }
        let total = Int(interval)
        return (total / 86400, (total % 86400) / 3600, (total % 3600) / 60, total % 60, false)
    }

    private var colonVisible: Bool {
        Int(now.timeIntervalSince1970) % 2 == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(displayLabel.uppercased())
                    .font(.nhg(14, .medium))
                    .foregroundColor(accent)
                    .tracking(3)

                if item.mode == .daily {
                    badge("DAILY")
                } else if item.mode == .nextEvent {
                    badge(resolved.title != nil ? "NEXT" : "EOD")
                }
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                Group {
                    if remaining.expired {
                        Text(item.mode == .daily ? "WAITING" : "00:00:00")
                            .font(.nhg(56, .bold))
                            .foregroundColor(accentDim)
                            .tracking(item.mode == .daily ? 2 : 0)
                    } else {
                        timeDisplay
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { copy(timeString) }
                .help("Click to copy · right-click for more options")

                if justCopied {
                    Text("COPIED")
                        .font(.nhg(11, .bold))
                        .tracking(2)
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(accent))
                        .offset(x: 6, y: -8)
                        .transition(.opacity)
                }
            }

            Text(item.subtitle)
                .font(.nhg(12, .medium))
                .foregroundColor(accentFaint)
                .tracking(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy time (\(timeString))") { copy(timeString) }
            Button("Copy label + time") { copy("\(item.label.uppercased()) \(timeString)") }
            Button("Copy target (\(item.absoluteTargetString(now: now)))") { copy(item.absoluteTargetString(now: now)) }
            Divider()
            Button("Edit…") { SettingsWindowController.shared.show() }
            Button(role: .destructive) {
                CountdownStore.shared.remove(id: item.id)
            } label: {
                Text("Delete \(item.label.uppercased())")
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.nhg(10, .bold))
            .tracking(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.15)))
            .foregroundColor(accent)
    }

    private var timeDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if remaining.d > 0 {
                digit(String(remaining.d))
                Text("d")
                    .font(.nhg(28, .medium))
                    .foregroundColor(accentDim)
                    .padding(.leading, 2)
                    .padding(.trailing, 14)
            }
            digit(String(format: "%02d", remaining.h))
            colon
            digit(String(format: "%02d", remaining.m))
            colon
            digit(String(format: "%02d", remaining.s))
        }
    }

    private func digit(_ s: String) -> some View {
        Text(s)
            .font(.nhg(64, .bold))
            .foregroundColor(accent)
    }

    private var colon: some View {
        Text(":")
            .font(.nhg(64, .bold))
            .foregroundColor(accent)
            .opacity(colonVisible ? 1.0 : 0.18)
            .padding(.horizontal, 2)
    }
}

struct HUDView: View {
    @ObservedObject var store: CountdownStore
    let now: Date
    let isHovering: Bool
    @State private var justCopied = false

    private var primary: Countdown? { store.items.first }
    private var colonVisible: Bool { Int(now.timeIntervalSince1970) % 2 == 0 }

    private func remaining(for item: Countdown) -> (d: Int, h: Int, m: Int, s: Int, expired: Bool) {
        let target = CountdownTarget.resolve(item, now: now,
                                             nextEventStart: EventKitService.shared.nextEvent?.startDate,
                                             nextEventTitle: EventKitService.shared.nextEvent?.title).date
        let interval = target.timeIntervalSince(now)
        if interval <= 0 { return (0, 0, 0, 0, true) }
        let total = Int(interval)
        return (total / 86400, (total % 86400) / 3600, (total % 3600) / 60, total % 60, false)
    }

    private func copy(_ s: String) {
        Pasteboard.copy(s)
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let item = primary {
                    Text(hudLabel(for: item).uppercased())
                        .font(.nhg(12, .medium))
                        .foregroundColor(item.color.swiftUIColor)
                        .tracking(2)
                    Spacer()
                    timeBody(for: item)
                } else {
                    Text("NO COUNTDOWNS")
                        .font(.nhg(12, .medium))
                        .foregroundColor(.bloombergOrangeDim)
                        .tracking(2)
                    Spacer()
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isHovering ? 0.18 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let item = primary else { return }
                copy(Countdown.formatRemaining(remaining(for: item), mode: item.mode))
            }
            .help("Click to copy · right-click for more options")
            .contextMenu {
                if let item = primary {
                    let r = remaining(for: item)
                    let ts = Countdown.formatRemaining(r, mode: item.mode)
                    Button("Copy time (\(ts))") { copy(ts) }
                    Button("Copy label + time") { copy("\(item.label.uppercased()) \(ts)") }
                    Button("Copy target (\(item.absoluteTargetString(now: now)))") { copy(item.absoluteTargetString(now: now)) }
                    Divider()
                    Button("Edit…") { SettingsWindowController.shared.show() }
                    Button(role: .destructive) {
                        store.remove(id: item.id)
                    } label: {
                        Text("Delete \(item.label.uppercased())")
                    }
                }
            }

            if justCopied, let item = primary {
                Text("COPIED")
                    .font(.nhg(10, .bold))
                    .tracking(2)
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(item.color.swiftUIColor))
                    .padding(.leading, 14)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
    }

    private func hudLabel(for item: Countdown) -> String {
        CountdownTarget.resolve(item, now: now,
                                nextEventStart: EventKitService.shared.nextEvent?.startDate,
                                nextEventTitle: EventKitService.shared.nextEvent?.title).title ?? item.label
    }

    @ViewBuilder
    private func timeBody(for item: Countdown) -> some View {
        let target = CountdownTarget.resolve(item, now: now,
                                             nextEventStart: EventKitService.shared.nextEvent?.startDate,
                                             nextEventTitle: EventKitService.shared.nextEvent?.title).date
        let interval = target.timeIntervalSince(now)
        if interval <= 0 {
            Text(item.mode == .daily ? "WAITING" : "00:00:00")
                .font(.nhg(22, .bold))
                .foregroundColor(item.color.swiftUIColor.opacity(0.55))
                .tracking(item.mode == .daily ? 1.5 : 0)
        } else {
            let total = Int(interval)
            let d = total / 86400
            let h = (total % 86400) / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            HStack(spacing: 0) {
                if d > 0 {
                    Text("\(d)d ")
                        .font(.nhg(22, .medium))
                        .foregroundColor(item.color.swiftUIColor.opacity(0.75))
                }
                Text(String(format: "%02d", h))
                    .font(.nhg(22, .bold))
                    .foregroundColor(item.color.swiftUIColor)
                Text(":")
                    .font(.nhg(22, .bold))
                    .foregroundColor(item.color.swiftUIColor)
                    .opacity(colonVisible ? 1.0 : 0.18)
                Text(String(format: "%02d", m))
                    .font(.nhg(22, .bold))
                    .foregroundColor(item.color.swiftUIColor)
                Text(":")
                    .font(.nhg(22, .bold))
                    .foregroundColor(item.color.swiftUIColor)
                    .opacity(colonVisible ? 1.0 : 0.18)
                Text(String(format: "%02d", s))
                    .font(.nhg(22, .bold))
                    .foregroundColor(item.color.swiftUIColor)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: CountdownStore
    @ObservedObject var settings: AppSettings
    @State private var showingNewEvent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Countdowns")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { showingNewEvent = true } label: { Label("New event", systemImage: "calendar.badge.plus") }
                Button { store.add() } label: { Label("Add", systemImage: "plus") }
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($store.items) { $item in
                        CountdownEditor(item: $item, onDelete: { store.remove(id: item.id) })
                    }
                    if store.items.isEmpty {
                        Text("No countdowns. Tap Add to create one.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    }
                }
            }
            .frame(maxHeight: 360)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Display")
                    .font(.system(size: 13, weight: .semibold))
                Toggle("HUD compact mode (one-line pill, primary countdown only)", isOn: $settings.hudMode)
                Toggle("Show in menu bar", isOn: $settings.menuBarEnabled)
            }

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .sheet(isPresented: $showingNewEvent) {
            NewEventForm(store: store)
        }
    }
}

struct CountdownEditor: View {
    @Binding var item: Countdown
    let onDelete: () -> Void
    @State private var calendarNote: String?
    @State private var isAddingEvent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Label", text: $item.label)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Picker("Mode", selection: $item.mode) {
                ForEach(CountdownMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: item.mode) { newMode in
                if newMode == .nextEvent && !EventKitService.shared.hasAccess {
                    EventKitService.shared.requestAccess { _ in }
                }
            }

            if item.mode == .nextEvent {
                nextEventControls
            }
            alertControls

            HStack(spacing: 8) {
                Text("COLOR")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                ForEach(TerminalColor.allCases) { color in
                    Button {
                        item.color = color
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        item.color == color ? Color.white : Color.white.opacity(0.15),
                                        lineWidth: item.color == color ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.displayName)
                }
                Spacer()
            }

            if item.mode == .fixed {
                DatePicker(
                    "Target",
                    selection: Binding(
                        get: { Date(timeIntervalSince1970: item.targetTimestamp) },
                        set: { item.targetTimestamp = $0.timeIntervalSince1970 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                calendarControls
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESETS AT")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        DatePicker(
                            "",
                            selection: hmBinding(\.resetHour, \.resetMinute),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COUNTS DOWN TO")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        DatePicker(
                            "",
                            selection: hmBinding(\.targetHour, \.targetMinute),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.gray.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder private var nextEventControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !EventKitService.shared.hasAccess {
                Text("Calendar access denied — enable in System Settings ▸ Privacy ▸ Calendars")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else if let ev = EventKitService.shared.nextEvent {
                Text("Next: \(ev.title) · \(Self.timeFmt.string(from: ev.startDate))")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text("No upcoming event — showing EOD")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Stepper("Imminent within \(item.eventLookaheadHours)h",
                    value: $item.eventLookaheadHours, in: 1...72)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder private var alertControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALERTS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary).tracking(1)
            HStack(spacing: 6) {
                ForEach([15, 10, 5, 1], id: \.self) { m in
                    let on = item.alertOffsets.contains(m)
                    Button("\(m)m") { toggleOffset(m) }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .secondary)
                }
                Spacer()
            }
            Toggle("Notify at zero", isOn: $item.alertAtZero)
                .font(.system(size: 11))
                .onChange(of: item.alertAtZero) { on in if on { requestNotifAuthIfNeeded() } }
        }
    }

    private func toggleOffset(_ m: Int) {
        if let idx = item.alertOffsets.firstIndex(of: m) {
            item.alertOffsets.remove(at: idx)
        } else {
            item.alertOffsets.append(m)
            item.alertOffsets.sort(by: >)
            requestNotifAuthIfNeeded()
        }
    }

    private func requestNotifAuthIfNeeded() {
        NotificationScheduler.shared.requestAuthorization { _ in }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f
    }()

    @ViewBuilder private var calendarControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper("Duration: \(durationLabel(item.eventDurationMinutes))",
                    value: $item.eventDurationMinutes, in: 15...480, step: 15)
                .font(.system(size: 11))
            HStack(spacing: 8) {
                Button(item.calendarEventID == nil ? "Add to Calendar" : "Update Calendar event") {
                    addOrUpdateCalendarEvent()
                }
                .buttonStyle(.bordered)
                .disabled(isAddingEvent)
                if item.calendarEventID != nil {
                    Text("Added ✓").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let calendarNote {
                Text(calendarNote).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func addOrUpdateCalendarEvent() {
        guard !isAddingEvent else { return }   // ignore rapid double-taps
        isAddingEvent = true
        calendarNote = nil
        let start = Date(timeIntervalSince1970: item.targetTimestamp)
        let title = item.label
        let dur = item.eventDurationMinutes
        if let id = item.calendarEventID {
            EventKitService.shared.updateEvent(id: id, title: title, start: start, durationMinutes: dur) { ok in
                if ok { isAddingEvent = false } else { createAndLink(title: title, start: start, dur: dur) }
            }
        } else {
            createAndLink(title: title, start: start, dur: dur)
        }
    }

    private func createAndLink(title: String, start: Date, dur: Int) {
        EventKitService.shared.createEvent(title: title, start: start, durationMinutes: dur) { newID in
            if let newID {
                item.calendarEventID = newID
            } else {
                calendarNote = EventKitService.shared.hasAccess
                    ? "Couldn't save to Calendar."
                    : "Calendar access denied — enable in System Settings ▸ Privacy ▸ Calendars"
            }
            isAddingEvent = false
        }
    }

    private func hmBinding(_ hourPath: WritableKeyPath<Countdown, Int>, _ minutePath: WritableKeyPath<Countdown, Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.dateFromHM(item[keyPath: hourPath], item[keyPath: minutePath])
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                item[keyPath: hourPath] = comps.hour ?? 0
                item[keyPath: minutePath] = comps.minute ?? 0
            }
        )
    }
}

struct NewEventForm: View {
    @ObservedObject var store: CountdownStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = "New event"
    @State private var start = Date().addingTimeInterval(3600)
    @State private var durationMinutes = 60
    @State private var note: String?
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New event").font(.system(size: 15, weight: .semibold))
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
            Stepper("Duration: \(durationLabel(durationMinutes))",
                    value: $durationMinutes, in: 15...480, step: 15)
            if let note {
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func create() {
        guard !isCreating else { return }   // ignore rapid double-taps
        isCreating = true
        note = nil
        let t = title.trimmingCharacters(in: .whitespaces)
        let s = start
        let dur = durationMinutes
        EventKitService.shared.createEvent(title: t, start: s, durationMinutes: dur) { newID in
            guard let newID else {
                note = EventKitService.shared.hasAccess
                    ? "Couldn't save to Calendar."
                    : "Calendar access denied — enable in System Settings ▸ Privacy ▸ Calendars"
                isCreating = false
                return
            }
            var c = Countdown(label: t)
            c.mode = .fixed
            c.targetTimestamp = s.timeIntervalSince1970
            c.eventDurationMinutes = dur
            c.calendarEventID = newID
            store.items.append(c)
            dismiss()
        }
    }
}
