import AppKit
import SwiftUI
import NetBarCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case menuBar, updates

    var id: Self { self }
    var title: String { self == .menuBar ? "菜单栏" : "软件更新" }
    var symbol: String { self == .menuBar ? "menubar.rectangle" : "arrow.triangle.2.circlepath" }
}

@MainActor
private final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .menuBar {
        willSet { if newValue != page { willSelect?() } }
    }
    var willSelect: (() -> Void)?
}

/// 页面与字体面板共用一个窗口生命周期；更新会话仍由应用持有。
@MainActor
final class SettingsController: NSViewController, NSFontChanging {
    static let windowSize = NSSize(width: 720, height: 580)
    private let preferences: MenuBarPreferences
    private let updates: UpdateController
    private let navigation = SettingsNavigation()

    var selectedPage: SettingsPage {
        get { navigation.page }
        set { navigation.page = newValue }
    }

    init(preferences: MenuBarPreferences, updates: UpdateController) {
        self.preferences = preferences
        self.updates = updates
        super.init(nibName: nil, bundle: nil)
        navigation.willSelect = { [weak self] in self?.closeFontPicker() }
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建设置窗口") }

    override func loadView() {
        let host = NSHostingController(rootView: SettingsRootView(
            navigation: navigation, preferences: preferences, updates: updates,
            chooseFont: { [weak self] in self?.showFontPicker() },
            closeFontPicker: { [weak self] in self?.closeFontPicker() }))
        addChild(host)
        view = host.view
    }

    static func makeWindow(preferences: MenuBarPreferences, updates: UpdateController) -> NSWindow {
        let controller = SettingsController(preferences: preferences, updates: updates)
        let window = NSWindow(contentViewController: controller)
        window.title = "NetBar 设置"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setFrame(NSRect(origin: window.frame.origin, size: windowSize), display: false)
        window.isReleasedWhenClosed = false
        return window
    }

    override var acceptsFirstResponder: Bool { true }

    func showFontPicker() {
        guard selectedPage == .menuBar, preferences.appearance.mode.showsSpeed,
              let window = view.window else { return }
        window.makeFirstResponder(self)
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(selectedFont, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    func changeFont(_ sender: NSFontManager?) {
        guard NSFontManager.shared.target === self,
              selectedPage == .menuBar, preferences.appearance.mode.showsSpeed,
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

private struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var updates: UpdateController
    let chooseFont: () -> Void
    let closeFontPicker: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: Binding<SettingsPage?>(
                    get: { navigation.page },
                    set: { if let page = $0 { navigation.page = page } })) {
                    ForEach(SettingsPage.allCases) { page in
                        Label {
                            Text(page.title).font(.system(size: 13))
                        } icon: {
                            Image(systemName: page.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background((page == .menuBar ? Color.blue : Color.gray).gradient,
                                            in: RoundedRectangle(cornerRadius: 5))
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 2)
                        .tag(page)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .tint(.blue)
                .accessibilityLabel("设置页面")
                Text("版本 \(updates.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
            }
            .padding(.top, 48)
            .frame(width: 200)
            .background(SettingsSidebarMaterial())

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(navigation.page.title)
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 52)
                ScrollView {
                    Group {
                        switch navigation.page {
                        case .menuBar:
                            MenuBarSettingsView(preferences: preferences, chooseFont: chooseFont,
                                                closeFontPicker: closeFontPicker)
                        case .updates:
                            UpdateSettingsView(updates: updates)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(navigation.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .font(.system(size: 13))
        .toggleStyle(.switch)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct SettingsSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .padding(.leading, 10)
            content
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))
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
        .padding(.vertical, 8)
        .frame(minHeight: 38)
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
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "显示内容") {
                SettingsGroup {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("菜单栏预览").font(.system(size: 13, weight: .medium))
                            Text("调整后即时生效").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(nsImage: MenuBarPresentation.image(
                            state: .available(NetworkSpeed(download: 2_560_000, upload: 128_600)),
                            appearance: preferences.appearance))
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel(preferences.appearance.mode.showsSpeed
                                ? "菜单栏样式预览，上排上传，下排下载" : "菜单栏样式预览，仅显示图标")
                    }
                    .padding(12)
                    Divider().padding(.horizontal, 12)
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
                    .padding(12)
                }
            }

            SettingsSection(title: "网速样式") {
                SettingsGroup {
                    SettingsRow(title: "显示方向箭头") {
                        Toggle("显示方向箭头", isOn: $preferences.appearance.showsArrows).labelsHidden()
                    }
                    Divider().padding(.horizontal, 12)
                    SettingsRow(title: "简洁单位", detail: "MB/s → M") {
                        Toggle("简洁单位", isOn: $preferences.appearance.compactUnits).labelsHidden()
                    }
                    Divider().padding(.horizontal, 12)
                    SettingsRow(title: "小数位数") {
                        Picker("小数位数", selection: $preferences.appearance.decimalPlaces) {
                            Text("0 位").tag(0)
                            Text("1 位").tag(1)
                            Text("2 位").tag(2)
                        }
                        .labelsHidden()
                        .frame(width: 86)
                    }
                    Divider().padding(.horizontal, 12)
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
                    Divider().padding(.horizontal, 12)
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
        VStack(alignment: .leading, spacing: 20) {
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
                    .padding(16)
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
                    Divider().padding(.horizontal, 12)
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
