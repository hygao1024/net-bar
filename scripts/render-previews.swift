import AppKit
import SwiftUI
import NetSpeedCore

/// 只生成本地视图图片，不显示窗口、不操作用户界面，也不启动采样。
@main
struct RenderPreviews {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let rows: [ProcessTraffic] = [
            sample("Google Chrome", bundle: "com.google.Chrome", fallback: 1234, down: 2_560_000, up: 34_200),
            sample("微信", bundle: "com.tencent.xinWeChat", fallback: 1235, down: 842_000, up: 128_600),
            sample("ChatGPT", bundle: "com.openai.codex", fallback: 1236, down: 156_200, up: 8_400),
            sample("网易邮箱大师", bundle: "com.netease.macmail", fallback: 1237, down: 24_800, up: 1_200),
            ProcessTraffic(pid: 416, name: "mDNSResponder", download: 1_400, upload: 640),
            ProcessTraffic(pid: 865, name: "Google Chrome Helper (Renderer)", download: 0, upload: 180),
            ProcessTraffic(pid: 1226, name: "com.apple.WebKit.Networking", download: 0, upload: 0),
            ProcessTraffic(pid: 400, name: "rapportd", download: 0, upload: 0),
            ProcessTraffic(pid: 360, name: "apsd", download: 0, upload: 0),
            ProcessTraffic(pid: 700, name: "sharingd", download: 0, upload: 0)
        ]
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            try render(TrafficPanel(rows: rows, updatedAt: date, errorMessage: nil), name: "\(mode)-traffic", dark: dark, output: output)
            let overflow = rows + (1...15).map {
                ProcessTraffic(pid: Int32(2000 + $0), name: "后台进程 \($0)", download: 0, upload: 0)
            }
            try render(TrafficPanel(rows: overflow, updatedAt: date, errorMessage: nil), name: "\(mode)-overflow", dark: dark, output: output)
            try render(TrafficPanel(rows: [], updatedAt: nil, errorMessage: nil), name: "\(mode)-loading", dark: dark, output: output)
            try render(TrafficPanel(rows: [], updatedAt: date, errorMessage: nil), name: "\(mode)-empty", dark: dark, output: output)
            try render(TrafficPanel(rows: [], updatedAt: nil, errorMessage: "采样超时，请重试。"), name: "\(mode)-error", dark: dark, output: output)
            try render(TrafficPanel(rows: rows, updatedAt: date, errorMessage: nil), name: "\(mode)-contrast", dark: dark, increasedContrast: true, output: output)
        }
        print("已生成界面预览：\(output.path)")
    }

    @MainActor private static func sample(_ name: String, bundle: String, fallback: Int32, down: Double, up: Double) -> ProcessTraffic {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier ?? fallback
        return ProcessTraffic(pid: pid, name: name, download: down, upload: up)
    }

    @MainActor private static func render(_ panel: TrafficPanel, name: String, dark: Bool, increasedContrast: Bool = false, output: URL) throws {
        let appearance: NSAppearance.Name = increasedContrast
            ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (dark ? .darkAqua : .aqua)
        NSApp.appearance = NSAppearance(named: appearance)
        let content = panel
            .environment(\.colorScheme, dark ? .dark : .light)
        let view = NSHostingView(rootView: content)
        let bounds = NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = view
        view.frame = bounds
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { fatalError("无法创建位图") }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("无法编码 PNG") }
        try data.write(to: output.appendingPathComponent("\(name).png"))
    }
}
