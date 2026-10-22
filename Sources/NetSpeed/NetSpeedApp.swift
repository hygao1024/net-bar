import AppKit
import SwiftUI
import NetSpeedCore

@main
struct NetSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor = TrafficMonitor()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "应用网速")
            button.image?.isTemplate = true
            button.toolTip = "应用网速 · 点击查看"
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        popover.contentViewController = NSHostingController(rootView: TrafficView(monitor: monitor))
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(suspendMonitoring), name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(suspendMonitoring), name: NSWorkspace.sessionDidResignActiveNotification, object: nil
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidShow(_ notification: Notification) { monitor.start() }
    func popoverWillClose(_ notification: Notification) { monitor.stop() }

    @objc private func suspendMonitoring() {
        popover.performClose(nil)
        monitor.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
