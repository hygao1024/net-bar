import AppKit
import CoreText
import NetBarCore

/// 在独立进程中验证真实菜单栏控件与系统计数；不操作现有应用或系统电源状态。
@main
struct CheckMenuBar {
    @MainActor private static func checkTextLayout() throws {
        var previews: [(String, NSImage)] = []
        for fontName in ["", "Menlo-Regular"] {
            for compact in [true, false] {
                for places in 0...2 {
                    var appearance = MenuBarAppearance()
                    appearance.mode = .speedOnly
                    appearance.showsArrows = false
                    appearance.compactUnits = compact
                    appearance.decimalPlaces = places
                    appearance.fontName = fontName
                    let font = MenuBarPresentation.font(named: fontName)
                    let number = "999" + (places == 0 ? "" : "." + String(repeating: "9", count: places))
                    let units = compact ? ["K", "M", "G"] : ["KB/s", "MB/s", "GB/s"]
                    let referenceWidth = units.map {
                        NSAttributedString(string: number + " " + $0, attributes: [.font: font]).size().width
                    }.max()!
                    let picture = MenuBarPresentation.image(
                        state: .available(NetworkSpeed(download: 225_000, upload: 22_000)), appearance: appearance)
                    guard picture.size.width == ceil(referenceWidth) + 2 else {
                        FileHandle.standardError.write(Data(
                            "文字区应按完整样例测量：实际 \(picture.size.width)，预期 \(ceil(referenceWidth) + 2) pt\n".utf8))
                        exit(1)
                    }
                    let bitmap = NSBitmapImageRep(data: picture.tiffRepresentation!)!
                    let scale = CGFloat(bitmap.pixelsWide) / picture.size.width
                    let rowEnds = (0..<2).map { row in
                        (0..<bitmap.pixelsWide).last { x in
                            let rows = (row * bitmap.pixelsHigh / 2)..<((row + 1) * bitmap.pixelsHigh / 2)
                            return rows.contains { bitmap.colorAt(x: x, y: $0)!.alphaComponent > 0.1 }
                        } ?? -1
                    }
                    guard CGFloat(abs(rowEnds[0] - rowEnds[1])) <= scale,
                          rowEnds.allSatisfy({ $0 >= 0 && CGFloat(bitmap.pixelsWide - 1 - $0) <= 3 * scale }) else {
                        FileHandle.standardError.write(Data("两行数值应在文字区域右侧同一位置结束\n".utf8))
                        exit(1)
                    }
                    if fontName.isEmpty {
                        previews.append(("\(compact ? "简洁单位" : "完整单位") · \(places) 位小数", picture))
                    }
                }
            }
        }
        for name in ["", "Menlo-Regular", "TimesNewRomanPS-ItalicMT"] {
            var widths: [CGFloat] = []
            for size in [7.0, 9.0, 12.0] {
                var appearance = MenuBarAppearance()
                appearance.fontName = name
                appearance.fontSize = size
                let font = MenuBarPresentation.font(named: name, size: size)
                let sample = NSAttributedString(string: "0123456789.KMGB/s—", attributes: [.font: font])
                let bounds = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(sample), .useGlyphPathBounds)
                precondition(bounds.height <= 10.01, "字号适配应为相邻两行留出间隙")
                let picture = MenuBarPresentation.image(
                    state: .available(NetworkSpeed(download: 225_000, upload: 22_000)), appearance: appearance)
                precondition(picture.size.height == 22, "字号设置不能撑高菜单栏")
                widths.append(picture.size.width)
                if name.isEmpty { previews.append(("系统字体 · \(size) pt", picture)) }
            }
            precondition(widths[0] < widths[1] && widths[1] < widths[2], "调整字号应实际改变文字尺寸")
        }
        let output = URL(fileURLWithPath: ".build/menu-bar-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // 将同一生产绘制器的结果放在浅色背景上，便于检查透明文字图像的留白。
        let sheet = NSImage(size: NSSize(width: 360, height: CGFloat(previews.count * 38 + 12)), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (index, preview) in previews.enumerated() {
                let y = rect.height - 35 - CGFloat(index * 38)
                NSAttributedString(string: preview.0, attributes: [.font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 12, y: y + 5))
                let area = NSRect(x: 210, y: y, width: preview.1.size.width + 16, height: 26)
                NSColor(white: 0.9, alpha: 1).setFill()
                NSBezierPath(roundedRect: area, xRadius: 5, yRadius: 5).fill()
                preview.1.draw(at: NSPoint(x: area.minX + 8, y: y + 2), from: .zero,
                               operation: .sourceOver, fraction: 1)
            }
            return true
        }
        let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: output.appendingPathComponent("text-layout.png"))
        print("完整样例宽度、两行右对齐、字号尺寸和字形高度验证通过")
    }

    @MainActor private static func checkNetworkPanel(_ delegate: AppDelegate, monitor: TrafficMonitor) async throws {
        delegate.menuBarPreferences.appearance.mode = .iconOnly
        delegate.showPanel()
        weak var controller = delegate.panel?.contentViewController
        precondition(delegate.panel?.isVisible == true)
        precondition(delegate.networkPanel.isVisible && monitor.isMonitoring)
        func finished(_ state: AddressLookupState) -> Bool {
            switch state {
            case .available, .unavailable: return true
            case .idle, .loading: return false
            }
        }
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(200))
            let snapshot = delegate.networkPanel.snapshot
            if !monitor.rows.isEmpty && finished(snapshot.ipv4) && finished(snapshot.ipv6) { break }
        }
        let snapshot = delegate.networkPanel.snapshot
        precondition(!snapshot.localReadFailed, "真实本机接口读取应成功")
        precondition(finished(snapshot.ipv4) && finished(snapshot.ipv6), "两种公网查询应在时限内独立结束")
        precondition(!monitor.rows.isEmpty, "真实 nettop 应提供进程样本")
        func status(_ state: AddressLookupState) -> String {
            if case .available(let value) = state { return value.countryCode == nil ? "已取得地址" : "已取得地址与地区" }
            return "暂不可用"
        }
        print("真实网络面板：本机地址 \(snapshot.localAddresses.count) 个，IPv4 \(status(snapshot.ipv4))，IPv6 \(status(snapshot.ipv6))")
        autoreleasepool {
            let window = delegate.panel!
            precondition(window.styleMask == [.borderless] && window.isKeyWindow, "面板应是可接收键盘的无边框窗口：style=\(window.styleMask.rawValue), key=\(window.isKeyWindow), active=\(NSApp.isActive)")
            precondition(window.frame.size == NSSize(width: PanelLayout.width, height: PanelLayout.height), "窗口不应再为箭头预留高度")
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
            window.sendEvent(escape)
        }
        precondition(delegate.panel == nil, "Esc 应关闭面板")
        precondition(controller == nil && !monitor.isMonitoring && monitor.rows.isEmpty)
        precondition(!delegate.networkPanel.isVisible && delegate.networkPanel.snapshot == NetworkPanelSnapshot())
        // 强制刷新后立即关闭，验证真实请求取消后的回调不能重新填充面板。
        delegate.showPanel()
        delegate.networkPanel.refreshAddresses(force: true)
        try await Task.sleep(for: .milliseconds(50))
        delegate.closePanel()
        try await Task.sleep(for: .milliseconds(1300))
        precondition(delegate.networkPanel.snapshot == NetworkPanelSnapshot())
        precondition(!monitor.isMonitoring && delegate.panel?.contentViewController == nil)
        delegate.showPanel()
        delegate.togglePanel()
        precondition(delegate.panel == nil && !monitor.isMonitoring, "再次点击菜单栏应关闭面板")
        delegate.togglePanel()
        precondition(delegate.panel?.isVisible == true, "快速重开应创建可见面板")
        delegate.showSettings()
        precondition(delegate.panel == nil && !monitor.isMonitoring && delegate.settingsWindow?.isVisible == true)
        delegate.settingsWindow?.close()

        delegate.showPanel()
        autoreleasepool {
            let other = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 100, height: 100),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            other.orderFront(nil)
            defer { other.close() }
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
                modifierFlags: [], timestamp: 0, windowNumber: other.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(click)
        }
        precondition(delegate.panel == nil && !monitor.isMonitoring, "点击同应用的其他窗口应关闭面板")
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            delegate.showPanel()
            NotificationCenter.default.post(name: name, object: NSApp)
            precondition(delegate.panel == nil && !monitor.isMonitoring, "离开应用或屏幕变化应关闭面板")
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            delegate.showPanel()
            center.post(name: name, object: nil)
            precondition(delegate.panel == nil && !monitor.isMonitoring, "休眠、离开会话或切换空间应关闭面板")
            center.post(name: NSWorkspace.didWakeNotification, object: nil)
            center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        }
        print("无箭头窗口、Esc、外部点击、设置切换、休眠关闭、快速重开及真实采样清理验证通过")
        delegate.menuBarPreferences.appearance = MenuBarAppearance()
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do {
                try await runChecks()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("菜单栏检查失败：\(error)\n".utf8))
                exit(1)
            }
        }
        // 键盘焦点与激活通知依赖真实 AppKit 事件循环，不能只运行异步调度队列。
        NSApp.run()
    }

    @MainActor private static func runChecks() async throws {
        try checkTextLayout()
        let screen = NSRect(x: -1440, y: 30, width: 1440, height: 870)
        for x in [-1440.0, -720.0, -20.0] {
            let anchor = NSRect(x: x, y: 900, width: 20, height: 24)
            let frame = MenuPanel.frame(below: anchor, visibleFrame: screen)
            guard screen.contains(frame) else {
                FileHandle.standardError.write(Data("面板定位超出菜单栏按钮所在屏幕的可见区域\n".utf8))
                exit(1)
            }
            guard frame.maxY == anchor.minY - 2 else {
                FileHandle.standardError.write(Data("面板与顶栏的间距应为 2 pt\n".utf8))
                exit(1)
            }
        }
        let suite = "NetBar.menuBarCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MenuBarPreferences(defaults: defaults)
        let monitor = TrafficMonitor()
        let delegate = AppDelegate(monitor: monitor, menuBarPreferences: preferences)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let item = delegate.statusItem!
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            NSStatusBar.system.removeStatusItem(item)
        }
        let button = item.button!
        precondition(delegate.panel?.contentViewController == nil)
        try await Task.sleep(for: .milliseconds(1400))
        precondition(button.toolTip?.contains("/s") == true, "真实网卡采样应更新菜单栏")
        print("真实菜单栏：\(button.toolTip!)")
        precondition(delegate.panel?.contentViewController == nil, "菜单栏刷新不应创建面板")

        // 检查真实窗口与按钮区域，不能用 length 属性代替系统最终占位。
        func occupiedWidth() -> CGFloat {
            guard let window = button.window else { preconditionFailure("菜单栏按钮缺少窗口") }
            guard abs(window.frame.width - button.bounds.width) <= 1 else {
                FileHandle.standardError.write(Data(
                    "菜单栏占位含额外留白：窗口 \(window.frame.width)，按钮 \(button.bounds.width)\n".utf8))
                exit(1)
            }
            return window.frame.width
        }
        let fullWidth = occupiedWidth()
        preferences.appearance.fontSize = 7
        try await Task.sleep(for: .milliseconds(150))
        let smallWidth = occupiedWidth()
        preferences.appearance.fontSize = 12
        try await Task.sleep(for: .milliseconds(150))
        precondition(occupiedWidth() > smallWidth, "设置字号应立即更新实际菜单栏")
        precondition(MenuBarPreferences(defaults: defaults).appearance.fontSize == 12)
        preferences.appearance.fontSize = 9
        try await Task.sleep(for: .milliseconds(150))
        precondition(abs(occupiedWidth() - fullWidth) <= 1)
        preferences.appearance.mode = .speedOnly
        try await Task.sleep(for: .milliseconds(150))
        let speedWidth = occupiedWidth()
        precondition(abs(fullWidth - speedWidth - 25) <= 1, "隐藏图标应收回图标及间距")
        preferences.appearance.showsArrows = false
        try await Task.sleep(for: .milliseconds(150))
        let noArrowsWidth = occupiedWidth()
        precondition(abs(speedWidth - noArrowsWidth - 10) <= 1, "隐藏箭头应收回箭头列")
        preferences.appearance.compactUnits = true
        try await Task.sleep(for: .milliseconds(150))
        let compactWidth = occupiedWidth()
        precondition(compactWidth < noArrowsWidth, "简洁单位应收回单位文字空间")
        preferences.appearance = MenuBarAppearance()
        try await Task.sleep(for: .milliseconds(150))
        precondition(abs(occupiedWidth() - fullWidth) <= 1, "恢复样式应恢复原有宽度")
        print("实际菜单栏占位：默认 \(fullWidth)，仅网速 \(speedWidth)，无箭头 \(noArrowsWidth)，简洁单位 \(compactWidth) pt")

        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        precondition(button.toolTip?.contains("等待网速样本") == true)
        try await Task.sleep(for: .milliseconds(1200))
        precondition(button.toolTip?.contains("等待网速样本") == true, "休眠期间应停止更新")
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(1200))
        precondition(button.toolTip?.contains("等待网速样本") == true, "会话仍未激活时不应恢复更新")
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        precondition(button.toolTip?.contains("等待网速样本") == true, "恢复后首先重建基准")
        try await Task.sleep(for: .milliseconds(1400))
        precondition(button.toolTip?.contains("/s") == true)

        let defaultWidth = occupiedWidth()
        preferences.appearance.mode = .iconOnly
        try await Task.sleep(for: .milliseconds(150))
        precondition(occupiedWidth() < defaultWidth, "仅图标模式应缩小实际占位")
        try await Task.sleep(for: .milliseconds(1200))
        precondition(button.toolTip == "NetBar · 点击查看应用明细")
        preferences.appearance.mode = .speedOnly
        preferences.appearance.compactUnits = true
        preferences.appearance.showsArrows = false
        preferences.appearance.decimalPlaces = 2
        preferences.appearance.fontName = "Menlo-Regular"
        try await Task.sleep(for: .milliseconds(150))
        precondition(occupiedWidth() < defaultWidth, "简洁无图标模式应更紧凑")
        precondition(button.toolTip?.contains("等待网速样本") == true)
        try await Task.sleep(for: .milliseconds(1400))
        precondition(button.toolTip?.contains("/s") == true, "重新启用网速应恢复采样")
        precondition(MenuBarPreferences(defaults: defaults).appearance == preferences.appearance)
        weak var releasedSettings: NSViewController?
        autoreleasepool {
            delegate.prepareSettings()
            let window = delegate.settingsWindow!
            releasedSettings = window.contentViewController
            let controller = window.contentViewController as! SettingsController
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            @MainActor func findSidebar(_ view: NSView) -> NSTableView? {
                if let table = view as? NSTableView { return table }
                return view.subviews.lazy.compactMap { findSidebar($0) }.first
            }
            guard let sidebar = findSidebar(controller.view) else {
                preconditionFailure("设置窗口缺少原生侧栏列表")
            }
            precondition(sidebar.numberOfRows == 2 && sidebar.selectedRow == 0,
                         "侧栏应展示两个页面并默认选中菜单栏")
            let originalSize = window.frame.size
            precondition(originalSize == SettingsController.windowSize, "设置窗口尺寸应包含标题栏：\(originalSize)")
            @MainActor func selectPage(_ row: Int) {
                sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
            selectPage(1)
            precondition(controller.selectedPage == .updates && sidebar.selectedRow == 1,
                         "选择侧栏更新项应切页并同步选中状态")
            selectPage(1)
            precondition(controller.selectedPage == .updates && sidebar.selectedRow == 1,
                         "重复选择当前页不能取消选中")
            precondition(window.frame.size == originalSize, "切换页面不应改变窗口尺寸")
            selectPage(0)
            precondition(controller.selectedPage == .menuBar && sidebar.selectedRow == 0)
            controller.showFontPicker()
            let manager = NSFontManager.shared
            let panel = manager.fontPanel(false)!
            precondition(manager.target === controller && panel.isVisible, "字体面板应属于当前设置窗口")
            precondition(controller.validModesForFontPanel(panel) == [.face, .collection], "字体面板只负责字族与字形")
            let originalFontSize = preferences.appearance.fontSize
            panel.setPanelFont(NSFont(name: "Menlo-Bold", size: 24)!, isMultiple: false)
            manager.modifyFontViaPanel(nil)
            precondition(preferences.appearance.fontName == "Menlo-Bold", "原生字体面板选择应即时生效")
            precondition(preferences.appearance.fontSize == originalFontSize, "字体面板不应绕过字号约束")
            precondition(MenuBarPreferences(defaults: defaults).appearance == preferences.appearance)
            selectPage(1)
            precondition(!panel.isVisible && manager.target == nil, "切页应关闭字体面板并清除目标")
            let savedFont = preferences.appearance.fontName
            controller.changeFont(manager)
            precondition(preferences.appearance.fontName == savedFont, "切页后的字体回调不能继续修改设置")
            controller.showFontPicker()
            precondition(!panel.isVisible, "软件更新页不能打开菜单栏字体面板")
            selectPage(0)
            preferences.appearance.mode = .iconOnly
            controller.showFontPicker()
            precondition(!panel.isVisible, "仅图标模式不能打开字体面板")
            preferences.appearance.mode = .speedOnly
            controller.showFontPicker()
            delegate.prepareSettings()
            precondition(window === delegate.settingsWindow, "设置窗口应复用")
            window.close()
            precondition(!panel.isVisible && manager.target == nil, "关闭设置应关闭字体面板并清除目标")
        }
        precondition(delegate.settingsWindow == nil && releasedSettings == nil, "关闭设置应释放视图")
        precondition(delegate.panel?.contentViewController == nil)
        preferences.appearance = MenuBarAppearance()

        if CommandLine.arguments.contains("--network") {
            try await checkNetworkPanel(delegate, monitor: monitor)
        }

        // 停止真实采样后，对同一个 NSStatusBarButton 渲染确定性的外观样本。
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        let output = URL(fileURLWithPath: ".build/menu-bar-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let samples: [(String, MenuBarSpeedState)] = [
            ("idle", .available(NetworkSpeed(download: 0, upload: 0))),
            ("traffic", .available(NetworkSpeed(download: 2_560_000, upload: 128_600))),
            ("maximum", .available(NetworkSpeed(download: 999_400_000_000, upload: 999_400_000_000))),
            ("error", .unavailable)
        ]
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            button.appearance = appearance
            for (name, state) in samples {
                MenuBarPresentation.update(button, state: state)
                try await Task.sleep(for: .milliseconds(100))
                precondition(abs(occupiedWidth() - fullWidth) <= 1, "网速变化不应改变实际占位")
                appearance.performAsCurrentDrawingAppearance {
                    button.layoutSubtreeIfNeeded()
                }
                let bounds = button.bounds
                let bitmap = button.bitmapImageRepForCachingDisplay(in: bounds)!
                appearance.performAsCurrentDrawingAppearance {
                    button.cacheDisplay(in: bounds, to: bitmap)
                }
                let data = bitmap.representation(using: .png, properties: [:])!
                try data.write(to: output.appendingPathComponent("\(dark ? "dark" : "light")-\(name).png"))
            }
        }
        for mode in MenuBarDisplayMode.allCases {
            for compact in [false, true] {
                for arrows in [false, true] {
                    for places in 0...2 {
                        var appearance = MenuBarAppearance()
                        appearance.mode = mode
                        appearance.compactUnits = compact
                        appearance.showsArrows = arrows
                        appearance.decimalPlaces = places
                        appearance.fontName = "Menlo-Regular"
                        let images = samples.map { MenuBarPresentation.image(state: $0.1, appearance: appearance) }
                        precondition(images.allSatisfy { $0.size == images[0].size && $0.isTemplate },
                                     "同一格式的宽度不应随数值或错误状态跳动")
                    }
                }
            }
        }
        var wideAppearance = MenuBarAppearance()
        wideAppearance.compactUnits = true
        wideAppearance.decimalPlaces = 0
        let ordinary = MenuBarPresentation.image(state: .available(NetworkSpeed(download: 999_000, upload: 0)),
                                                appearance: wideAppearance)
        let wide = MenuBarPresentation.image(state: .available(NetworkSpeed(download: 1_000_000_000_000_000, upload: 0)),
                                             appearance: wideAppearance)
        precondition(wide.size.width > ordinary.size.width, "最高单位的大数值应扩展宽度，不截断或封顶")
        let fallback = MenuBarPresentation.font(named: "not-an-installed-font")
        precondition(fallback == MenuBarPresentation.font(named: ""), "缺失字体应回退到系统字体")
        print("菜单栏设置即时生效、保存恢复、窗口释放、格式组合验证通过")
        print("菜单栏真实采样、休眠／会话恢复与按需面板验证通过；预览位于 \(output.path)")
    }
}
