import AppKit
import SwiftUI
import NetBarCore

struct MenuBarSettingsView: View {
    static let width: CGFloat = 480
    static let height: CGFloat = 500

    @ObservedObject var preferences: MenuBarPreferences
    private let fonts: [String]

    init(preferences: MenuBarPreferences) {
        self.preferences = preferences
        fonts = NSFontManager.shared.availableFonts.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: MenuBarPresentation.image(
                    state: .available(NetworkSpeed(download: 2_560_000, upload: 128_600)),
                    appearance: preferences.appearance))
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("菜单栏样式预览")
                Text(preferences.appearance.mode.showsSpeed ? "样式预览 · 上排上传，下排下载" : "样式预览 · 仅显示应用图标")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Form {
                Section {
                    Picker("显示内容", selection: $preferences.appearance.mode) {
                        Text("图标与网速").tag(MenuBarDisplayMode.iconAndSpeed)
                        Text("仅网速").tag(MenuBarDisplayMode.speedOnly)
                        Text("仅图标").tag(MenuBarDisplayMode.iconOnly)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("菜单栏显示内容")
                } header: {
                    Text("菜单栏")
                }

                Section {
                    Toggle("显示上传、下载箭头", isOn: $preferences.appearance.showsArrows)
                    Toggle("简洁单位", isOn: $preferences.appearance.compactUnits)
                        .help("用 K、M、G 代替 KB/s、MB/s、GB/s")
                    Picker("小数位数", selection: $preferences.appearance.decimalPlaces) {
                        Text("0 位").tag(0)
                        Text("1 位").tag(1)
                        Text("2 位").tag(2)
                    }
                    Picker("网速字体", selection: $preferences.appearance.fontName) {
                        Text("系统默认（等宽数字）").tag("")
                        if !preferences.appearance.fontName.isEmpty,
                           !fonts.contains(preferences.appearance.fontName) {
                            Text("原字体不可用（使用系统默认）").tag(preferences.appearance.fontName)
                        }
                        ForEach(fonts, id: \.self) { name in
                            Text(NSFont(name: name, size: 9)?.displayName ?? name).tag(name)
                        }
                    }
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(preferences.appearance.fontSize, specifier: "%.1f") pt")
                            .monospacedDigit()
                        Stepper("字号", value: $preferences.appearance.fontSize,
                                in: MenuBarAppearance.fontSizeRange, step: 0.5)
                            .labelsHidden()
                            .accessibilityValue("\(preferences.appearance.fontSize, specifier: "%.1f") 磅")
                    }
                    .help("7–12 pt，每次调整 0.5 pt；过高的字形会适配菜单栏行高")
                } header: {
                    Text("网速样式")
                } footer: {
                    Text(preferences.appearance.mode.showsSpeed
                         ? "字体与字号仅用于菜单栏；过高的字形会自动适配两行高度。"
                         : "仅图标时暂停菜单栏网速采样，网速样式仍会保留。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!preferences.appearance.mode.showsSpeed)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)

            HStack {
                Text("更改自动保存")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") { preferences.appearance = MenuBarAppearance() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

enum SettingsPage: String, CaseIterable {
    case menuBar = "菜单栏"
    case updates = "软件更新"
}

struct SettingsView: View {
    static let width: CGFloat = 480
    static let height: CGFloat = 560
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var updates: UpdateController
    @State var page: SettingsPage = .menuBar

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置", selection: $page) {
                ForEach(SettingsPage.allCases, id: \.self) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.vertical, 16)
            Divider()
            if page == .menuBar {
                MenuBarSettingsView(preferences: preferences)
            } else {
                UpdateSettingsView(updates: updates)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController

    private var appIcon: NSImage {
        NSImage(size: NSSize(width: 80, height: 80), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            BrandIcon.drawAppIcon(in: rect, context: context)
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: appIcon).accessibilityHidden(true)
                Text("NetBar").font(.system(size: 24, weight: .semibold))
                Text("版本 \(updates.version)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.top, 18)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    if updates.status.isBusy {
                        ProgressView().controlSize(.small).frame(width: 24)
                    } else {
                        Image(systemName: statusSymbol)
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(statusColor)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(updates.status.title).font(.system(size: 13, weight: .semibold))
                        Text(updates.status.detail)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Text(lastCheckText).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(action: { updates.checkForUpdates() }) {
                        Text(checkTitle).frame(minWidth: 70)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updates.canCheck)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.35)))
            .padding(.horizontal, 24)

            Form {
                Section {
                    Toggle(isOn: Binding(get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动检查更新")
                            Text("每天检查，及时获取新版本。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: Binding(get: { updates.automaticDownloads }, set: { updates.setAutomaticDownloads($0) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动下载并安装")
                            Text("后台下载，退出时安装；需要授权时会提示。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!updates.automaticChecks)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .disabled(!updates.isEnabled)

            HStack(spacing: 4) {
                Text("更新来自 GitHub").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Link("查看发布说明", destination: UpdateController.releasesURL)
            }
            .font(.system(size: 11))
            .padding(.bottom, 18)
        }
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheck else { return "尚未检查更新" }
        return "上次检查：\(date.formatted(date: .abbreviated, time: .shortened))"
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
