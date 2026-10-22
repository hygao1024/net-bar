import AppKit
import SwiftUI
import NetSpeedCore

struct MenuBarSettingsView: View {
    static let width: CGFloat = 420
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
