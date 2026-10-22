import AppKit
import SwiftUI
import NetSpeedCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor: TrafficMonitor
    private let loginItem = LoginItemController()
    private let preferences = PanelPreferences()
    private var statusItem: NSStatusItem?
    let popover = NSPopover()

    override convenience init() {
        self.init(monitor: TrafficMonitor())
    }

    init(monitor: TrafficMonitor) {
        self.monitor = monitor
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = BrandIcon.statusBarImage()
            button.toolTip = "应用网速 · 点击查看"
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(suspendMonitoring), name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(suspendMonitoring), name: NSWorkspace.sessionDidResignActiveNotification, object: nil
        )
    }

    func preparePanel() {
        guard popover.contentViewController == nil else { return }
        popover.contentViewController = NSHostingController(rootView:
            TrafficView(monitor: monitor, loginItem: loginItem, preferences: preferences))
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            preparePanel()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        loginItem.refresh()
        monitor.start()
    }
    func applicationDidBecomeActive(_ notification: Notification) { loginItem.refresh() }
    func popoverWillClose(_ notification: Notification) { monitor.stop() }

    func popoverDidClose(_ notification: Notification) {
        // 关闭完成后再拆除视图，避免影响关闭回调；快速重开时保留新面板。
        guard !popover.isShown else { return }
        popover.contentViewController = nil
    }

    @objc private func suspendMonitoring() {
        popover.performClose(nil)
        monitor.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
