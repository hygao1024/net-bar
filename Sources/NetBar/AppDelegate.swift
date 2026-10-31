import AppKit
import SwiftUI
import NetBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let monitor: TrafficMonitor
    private let loginItem = LoginItemController()
    private let preferences = PanelPreferences()
    let menuBarPreferences: MenuBarPreferences
    let updates = UpdateController()
    private(set) var settingsWindow: NSWindow?
    let networkPanel = NetworkPanelModel()
    private let menuBarMonitor = MenuBarSpeedMonitor()
    private var isAwake = true
    private var isSessionActive = true
    private(set) var statusItem: NSStatusItem?
    private(set) var panel: MenuPanel?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

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
        updates.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            MenuBarPresentation.configure(button)
            button.target = self
            button.action = #selector(togglePanel)
        }
        menuBarMonitor.onChange = { [weak self] _ in self?.updateMenuBar() }
        menuBarPreferences.onChange = { [weak self] in
            self?.synchronizeMenuBarMonitoring()
            self?.updateMenuBar()
        }
        synchronizeMenuBarMonitoring()
        updateMenuBar()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(workspaceStateChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(dismissPanel), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(dismissPanel), name: name, object: nil)
        }
    }

    func preparePanel() {
        guard panel == nil else { return }
        let window = MenuPanel()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView:
            TrafficView(monitor: monitor, loginItem: loginItem, preferences: preferences, networkPanel: networkPanel,
                        openSettings: { [weak self] in self?.showSettings() }))
        panel = window
    }

    @objc func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard isAwake, isSessionActive, statusItem?.button?.window?.screen != nil else { return }
        preparePanel()
        guard let window = panel else { return }
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.isVisible else { closePanel(); return }
        installPanelClickMonitors()
        loginItem.refresh()
        networkPanel.start()
        monitor.start()
    }

    func closePanel() {
        panel?.close()
    }

    @objc private func dismissPanel(_ notification: Notification) { closePanel() }

    private func positionPanel() {
        guard let panel, let button = statusItem?.button,
              let anchorWindow = button.window, let screen = anchorWindow.screen else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrame(MenuPanel.frame(below: anchor, visibleFrame: screen.visibleFrame), display: true)
    }

    private func installPanelClickMonitors() {
        guard let window = panel, localClickMonitor == nil, globalClickMonitor == nil else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self, weak window] event in
            guard let self, let window, self.panel === window else { return event }
            // 菜单栏按钮自己处理开关，不能在 mouseDown 关闭后被按钮的 mouseUp 重新打开。
            if event.window !== window, event.window !== self.statusItem?.button?.window {
                self.closePanel()
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self, weak window] _ in
            guard let self, let window, self.panel === window else { return }
            self.closePanel()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) { loginItem.refresh() }

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
            closePanel()
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
        if panel?.isVisible == true { positionPanel() }
    }

    func showSettings() {
        closePanel()
        prepareSettings()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func prepareSettings() {
        if settingsWindow == nil {
            let window = SettingsController.makeWindow(preferences: menuBarPreferences, updates: updates)
            window.delegate = self
            window.center()
            settingsWindow = window
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === panel {
            if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
            if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
            localClickMonitor = nil
            globalClickMonitor = nil
            monitor.stop()
            networkPanel.stop()
            panel = nil
            window.contentViewController = nil
            return
        }
        guard window === settingsWindow else { return }
        (window.contentViewController as? SettingsController)?.closeFontPicker()
        window.contentViewController = nil
        settingsWindow = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarPreferences.onChange = nil
        menuBarMonitor.onChange = nil
        closePanel()
        networkPanel.stop()
        settingsWindow?.close()
        menuBarMonitor.stop()
        monitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
final class MenuPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        title = "NetBar"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }

    static func frame(below anchor: NSRect, visibleFrame: NSRect) -> NSRect {
        let area = visibleFrame.insetBy(dx: 8, dy: 8)
        let size = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        let x = max(area.minX, min(anchor.midX - size.width / 2, area.maxX - size.width))
        let y = max(area.minY, min(anchor.minY - 2 - size.height, visibleFrame.maxY - 2 - size.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}
