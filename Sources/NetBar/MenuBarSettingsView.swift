import AppKit
import SwiftUI
import NetBarCore

/// 页面与字体面板共用一个窗口生命周期；更新会话仍由应用持有。
@MainActor
final class SettingsController: NSTabViewController, NSFontChanging {
    static let contentSize = NSSize(width: 440, height: 418)
    private let preferences: MenuBarPreferences

    init(preferences: MenuBarPreferences, updates: UpdateController) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        canPropagateSelectedChildViewControllerTitle = false
        let menuBar = NSHostingController(rootView: SettingsPageContent {
            MenuBarSettingsView(preferences: preferences,
                                chooseFont: { [weak self] in self?.showFontPicker() },
                                closeFontPicker: { [weak self] in self?.closeFontPicker() })
        })
        let update = NSHostingController(rootView: SettingsPageContent {
            UpdateSettingsView(updates: updates)
        })
        for (controller, title, symbol) in [
            (menuBar as NSViewController, "菜单栏", "menubar.rectangle"),
            (update as NSViewController, "软件更新", "arrow.triangle.2.circlepath")
        ] {
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            addTabViewItem(item)
        }
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建设置窗口") }

    static func makeWindow(preferences: MenuBarPreferences, updates: UpdateController) -> NSWindow {
        let controller = SettingsController(preferences: preferences, updates: updates)
        let window = NSWindow(contentViewController: controller)
        window.title = "NetBar 设置"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .unifiedCompact
        window.toolbar?.displayMode = .iconOnly
        window.toolbar?.allowsUserCustomization = false
        window.setContentSize(contentSize)
        window.isReleasedWhenClosed = false
        return window
    }

    override func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + super.toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace]
    }

    override func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                          willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let item = super.toolbar(toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: flag) else {
            return nil
        }
        guard let index = tabViewItems.firstIndex(where: { ($0.identifier as? String) == identifier.rawValue }) else {
            return item
        }
        let button = NSButton(title: item.label, target: self, action: #selector(selectPage(_:)))
        button.image = item.image?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.setButtonType(.pushOnPushOff)
        button.tag = index
        button.state = selectedTabViewItemIndex == index ? .on : .off
        button.toolTip = item.label
        item.view = button
        return item
    }

    @objc private func selectPage(_ sender: NSButton) {
        selectedTabViewItemIndex = sender.tag
        sender.state = .on
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        for item in view.window?.toolbar?.items ?? [] {
            guard let button = item.view as? NSButton else { continue }
            button.state = button.tag == selectedTabViewItemIndex ? .on : .off
        }
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        closeFontPicker()
        super.tabView(tabView, willSelect: tabViewItem)
    }

    override var acceptsFirstResponder: Bool { true }

    func showFontPicker() {
        guard selectedTabViewItemIndex == 0, preferences.appearance.mode.showsSpeed,
              let window = view.window else { return }
        window.makeFirstResponder(self)
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(selectedFont, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    func changeFont(_ sender: NSFontManager?) {
        guard NSFontManager.shared.target === self,
              selectedTabViewItemIndex == 0, preferences.appearance.mode.showsSpeed,
              let sender else { return }
        preferences.appearance.fontName = sender.convert(selectedFont).fontName
    }

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        // 字号由设置页限制在菜单栏可用范围；颜色和装饰不属于字体设置。
        [.face, .collection]
    }

    func closeFontPicker() {
        let manager = NSFontManager.shared
        guard manager.target === self else { return }
        manager.fontPanel(false)?.orderOut(nil)
        manager.target = nil
    }

    private var selectedFont: NSFont {
        NSFont(name: preferences.appearance.fontName, size: preferences.appearance.fontSize)
            ?? .monospacedDigitSystemFont(ofSize: preferences.appearance.fontSize, weight: .medium)
    }
}

private struct SettingsPageContent<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content.padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 13))
        .toggleStyle(.switch)
        .controlSize(.small)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: SettingsController.contentSize.width, height: SettingsController.contentSize.height)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium))
            content
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5))
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
    }
}

struct MenuBarSettingsView: View {
    @ObservedObject var preferences: MenuBarPreferences
    var chooseFont: () -> Void
    var closeFontPicker: () -> Void

    private var fontLabel: String {
        let name = preferences.appearance.fontName
        guard !name.isEmpty else { return "系统默认" }
        return NSFont(name: name, size: 9)?.displayName ?? "系统默认（原字体不可用）"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 5) {
                Image(nsImage: MenuBarPresentation.image(
                    state: .available(NetworkSpeed(download: 2_560_000, upload: 128_600)),
                    appearance: preferences.appearance))
                    .accessibilityLabel(preferences.appearance.mode.showsSpeed
                                         ? "菜单栏样式预览，上排上传，下排下载" : "菜单栏样式预览，仅显示图标")
                Text("菜单栏预览").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            SettingsSection(title: "显示内容") {
                Picker("显示内容", selection: Binding(
                    get: { preferences.appearance.mode },
                    set: { closeFontPicker(); preferences.appearance.mode = $0 })) {
                    Text("图标与网速").tag(MenuBarDisplayMode.iconAndSpeed)
                    Text("仅网速").tag(MenuBarDisplayMode.speedOnly)
                    Text("仅图标").tag(MenuBarDisplayMode.iconOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("菜单栏显示内容")
            }

            SettingsSection(title: "网速样式") {
                SettingsGroup {
                    SettingsRow(title: "显示方向箭头") {
                        Toggle("显示方向箭头", isOn: $preferences.appearance.showsArrows).labelsHidden()
                    }
                    Divider().padding(.leading, 12)
                    SettingsRow(title: "简洁单位", detail: "MB/s → M") {
                        Toggle("简洁单位", isOn: $preferences.appearance.compactUnits).labelsHidden()
                    }
                    Divider().padding(.leading, 12)
                    SettingsRow(title: "小数位数") {
                        Picker("小数位数", selection: $preferences.appearance.decimalPlaces) {
                            Text("0 位").tag(0)
                            Text("1 位").tag(1)
                            Text("2 位").tag(2)
                        }
                        .labelsHidden()
                        .frame(width: 72)
                    }
                    Divider().padding(.leading, 12)
                    SettingsRow(title: "字体") {
                        Text(fontLabel).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(fontLabel)
                        Menu("选择…") {
                            Button("系统默认（等宽数字）") {
                                closeFontPicker()
                                preferences.appearance.fontName = ""
                            }
                            Button("其他字体…", action: chooseFont)
                        }
                        .fixedSize()
                        .accessibilityLabel("选择菜单栏字体")
                    }
                    Divider().padding(.leading, 12)
                    SettingsRow(title: "字号") {
                        Text("\(preferences.appearance.fontSize, specifier: "%.1f") pt").monospacedDigit()
                        Stepper("字号", value: $preferences.appearance.fontSize,
                                in: MenuBarAppearance.fontSizeRange, step: 0.5)
                            .labelsHidden()
                            .accessibilityValue("\(preferences.appearance.fontSize, specifier: "%.1f") 磅")
                    }
                    .help("7–12 pt，每次调整 0.5 pt；过高的字形会适配菜单栏行高")
                }
                .disabled(!preferences.appearance.mode.showsSpeed)
                if !preferences.appearance.mode.showsSpeed {
                    Text("仅图标时暂停网速采样，保留样式设置。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("更改自动保存").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") {
                    closeFontPicker()
                    preferences.appearance = MenuBarAppearance()
                }
            }
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController

    private var appIcon: NSImage {
        NSImage(size: NSSize(width: 48, height: 48), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            BrandIcon.drawAppIcon(in: rect, context: context)
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: appIcon).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NetBar").font(.system(size: 15, weight: .semibold))
                    Text("版本 \(updates.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: "更新状态") {
                SettingsGroup {
                    HStack(spacing: 12) {
                        if updates.status.isBusy {
                            ProgressView().controlSize(.small).frame(width: 24)
                        } else {
                            Image(systemName: statusSymbol).font(.system(size: 22))
                                .foregroundStyle(statusColor).frame(width: 24).accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusTitle).font(.system(size: 13, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(updates.status.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(checkTitle, action: { updates.checkForUpdates() })
                            .buttonStyle(.borderedProminent)
                            .disabled(!updates.canCheck)
                            .fixedSize()
                    }
                    .padding(12)
                }
                if let date = updates.lastCheck {
                    Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: "自动更新") {
                SettingsGroup {
                    SettingsRow(title: "自动检查更新", detail: "每天检查一次") {
                        Toggle("自动检查更新", isOn: Binding(
                            get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
                            .labelsHidden()
                    }
                    Divider().padding(.leading, 12)
                    SettingsRow(title: "自动下载并安装", detail: "后台下载，退出 NetBar 时安装") {
                        Toggle("自动下载并安装", isOn: Binding(
                            get: { updates.automaticDownloads }, set: { updates.setAutomaticDownloads($0) }))
                            .labelsHidden()
                            .disabled(!updates.automaticChecks)
                    }
                }
                .disabled(!updates.isEnabled)
                Text("需要安装授权时会提示").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Link("查看发布说明", destination: UpdateController.releasesURL)
                Text("更新来自 GitHub").foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
        }
    }

    private var statusTitle: String {
        if case .idle = updates.status, updates.lastCheck != nil { return "检查软件更新" }
        return updates.status.title
    }

    private var checkTitle: String {
        switch updates.status {
        case .ready: return "安装更新…"
        case .available: return "查看更新…"
        case .failed: return "重试检查"
        default: return "检查更新"
        }
    }

    private var statusSymbol: String {
        switch updates.status {
        case .current: return "checkmark.circle"
        case .available, .ready: return "arrow.down.circle"
        case .failed, .unavailable: return "exclamationmark.circle"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch updates.status {
        case .current: return .green
        case .failed, .unavailable: return .secondary
        default: return .accentColor
        }
    }
}
