import SwiftUI
import AppKit
import ServiceManagement
import Combine

final class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(store: CountdownStore.shared, settings: AppSettings.shared)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Countdowns"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: FloatingWindow!
    private var cancellables = Set<AnyCancellable>()

    private func rescheduleNotifications() {
        let svc = EventKitService.shared
        NotificationScheduler.shared.reschedule(
            items: CountdownStore.shared.items,
            nextEventStart: svc.nextEvent?.startDate,
            nextEventTitle: svc.nextEvent?.title)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView()

        // .resizable enables edge/corner drag-to-resize. WindowSizer pins the
        // window's aspectRatio to the content shape so dragging scales both
        // dimensions together and the content always fills (no black void).
        window = FloatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: content)
        WindowSizer.shared.window = window

        if let frameStr = UserDefaults.standard.string(forKey: "windowFrame") {
            // Restore saved position + width; height is re-fit to content on layout.
            window.setFrame(NSRectFromString(frameStr), display: true)
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - 420, y: f.maxY - 230))
        }
        WindowSizer.shared.applyResizeConstraints()
        window.makeKeyAndOrderFront(nil)

        let nc = NotificationCenter.default
        let save = { [weak self] (_: Notification) in
            guard let w = self?.window else { return }
            UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: "windowFrame")
            // Keep userScale aligned with a drag-resized frame (no-op for moves).
            WindowSizer.shared.syncScaleFromFrame()
        }
        nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save)
        nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: save)

        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        EventKitService.shared.start()

        // Reschedule notifications when items, the next event, or time (daily roll) change.
        CountdownStore.shared.$items
            .sink { [weak self] _ in self?.rescheduleNotifications() }
            .store(in: &cancellables)
        EventKitService.shared.$nextEvent
            .sink { [weak self] _ in self?.rescheduleNotifications() }
            .store(in: &cancellables)
        let reschedTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.rescheduleNotifications()
        }
        RunLoop.main.add(reschedTimer, forMode: .common)
        rescheduleNotifications()

        registerLoginItem()
        MenuBarController.shared.refresh()
    }

    private func registerLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status != .enabled {
                    try service.register()
                }
            } catch {
                NSLog("Countdown: SMAppService register failed: \(error.localizedDescription)")
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
