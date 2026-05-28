import AppKit
import SwiftUI

final class MenuBarController {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var timer: Timer?

    private init() {}

    func refresh() {
        if AppSettings.shared.menuBarEnabled {
            enable()
        } else {
            disable()
        }
    }

    private func enable() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.font = NSFont(name: "NeueHaasDisplay-Mediu", size: 13) ?? NSFont.menuBarFont(ofSize: 13)
        statusItem = item
        startTimer()
    }

    private func disable() {
        timer?.invalidate()
        timer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    @objc private func clicked(_ sender: AnyObject) {
        guard let w = WindowSizer.shared.window else { return }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func startTimer() {
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let button = statusItem?.button else { return }
        let items = CountdownStore.shared.items
        guard let primary = items.first else {
            button.title = "—"
            return
        }
        let now = Date()
        let target = primary.currentTarget(now: now)
        let interval = target.timeIntervalSince(now)
        let label = primary.label.uppercased()
        let body: String
        if interval <= 0 {
            body = primary.mode == .daily ? "WAITING" : "00:00:00"
        } else {
            let total = Int(interval)
            let d = total / 86400
            let h = (total % 86400) / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if d > 0 {
                body = String(format: "%dd %02d:%02d", d, h, m)
            } else {
                body = String(format: "%02d:%02d:%02d", h, m, s)
            }
        }
        button.title = "\(label)  \(body)"
    }
}
