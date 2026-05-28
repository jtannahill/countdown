import SwiftUI
import AppKit
import ServiceManagement

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView()

        // No .resizable: OS edge-dragging would stretch the window independently
        // of its content, leaving a black void. Resizing is done only via the
        // in-app handle (WindowSizer.setUserScale), which scales content to fit.
        window = FloatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
            styleMask: [.borderless],
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
            window.setFrame(NSRectFromString(frameStr), display: true)
            // Pin to the saved frame so content layout doesn't drift it on launch.
            WindowSizer.shared.honorSavedFrame = true
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - 420, y: f.maxY - 230))
        }
        window.makeKeyAndOrderFront(nil)

        let nc = NotificationCenter.default
        let save = { [weak self] (_: Notification) in
            guard let w = self?.window else { return }
            UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: "windowFrame")
        }
        nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save)
        nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: save)

        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

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
