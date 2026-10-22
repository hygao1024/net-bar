import AppKit
import SwiftUI
import NetSpeedCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let monitor: TrafficMonitor
    private let loginItem = LoginItemController()
    private let preferences = PanelPreferences()
    let menuBarPreferences: MenuBarPreferences
    private(set) var settingsWindow: NSWindow?
    let networkPanel = NetworkPanelModel()
    private let menuBarMonitor = MenuBarSpeedMonitor()
    private var isAwake = true
    private var isSessionActive = true
    private(set) var statusItem: NSStatusItem?
    let popover = NSPopover()

    override convenience init() {
        self.init(monitor: TrafficMonitor())
    }

    init(monitor: TrafficMonitor, menuBarPreferences: MenuBarPreferences = MenuBarPreferences()) {
        self.monitor = monitor
        self.menuBarPreferences = menuBarPreferences
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            MenuBarPresentation.configure(button)
            button.target = self
            button.action = #selector(togglePopover)
        }
        menuBarMonitor.onChange = { [weak self] _ in self?.updateMenuBar() }
        menuBarPreferences.onChange = { [weak self] in
            self?.synchronizeMenuBarMonitoring()
            self?.updateMenuBar()
        }
        synchronizeMenuBarMonitoring()
        updateMenuBar()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(workspaceStateChanged), name: name, object: nil)
        }
    }

    func preparePanel() {
        guard popover.contentViewController == nil else { return }
        popover.contentViewController = NSHostingController(rootView:
            TrafficView(monitor: monitor, loginItem: loginItem, preferences: preferences, networkPanel: networkPanel,
                        openSettings: { [weak self] in self?.showSettings() }))
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
        networkPanel.start()
        monitor.start()
    }
    func applicationDidBecomeActive(_ notification: Notification) { loginItem.refresh() }
    func popoverWillClose(_ notification: Notification) {
        monitor.stop()
        networkPanel.stop()
    }

    func popoverDidClose(_ notification: Notification) {
        // 关闭完成后再拆除视图，避免影响关闭回调；快速重开时保留新面板。
        guard !popover.isShown else { return }
        popover.contentViewController = nil
    }

    @objc private func workspaceStateChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: isAwake = false
        case NSWorkspace.didWakeNotification: isAwake = true
        case NSWorkspace.sessionDidResignActiveNotification: isSessionActive = false
        case NSWorkspace.sessionDidBecomeActiveNotification: isSessionActive = true
        default: return
        }
        synchronizeMenuBarMonitoring()
        if !isAwake || !isSessionActive {
            popover.performClose(nil)
            monitor.stop()
        }
    }

    private func synchronizeMenuBarMonitoring() {
        if isAwake && isSessionActive && menuBarPreferences.appearance.mode.showsSpeed {
            menuBarMonitor.start()
        } else {
            menuBarMonitor.stop()
        }
    }

    private func updateMenuBar() {
        guard let item = statusItem, let button = item.button else { return }
        MenuBarPresentation.update(button, state: menuBarMonitor.state,
                                   appearance: menuBarPreferences.appearance)
    }

    func showSettings() {
        popover.performClose(nil)
        prepareSettings()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func prepareSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: MenuBarSettingsView(preferences: menuBarPreferences))
            let window = NSWindow(contentViewController: controller)
            window.title = "菜单栏设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        window.contentViewController = nil
        settingsWindow = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarPreferences.onChange = nil
        menuBarMonitor.onChange = nil
        networkPanel.stop()
        settingsWindow?.close()
        menuBarMonitor.stop()
        monitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
