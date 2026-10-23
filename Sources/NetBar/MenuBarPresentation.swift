import AppKit
import CoreText
import NetBarCore

@MainActor
enum MenuBarPresentation {
    static func configure(_ button: NSButton) {
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
    }

    static func update(_ button: NSButton, state: MenuBarSpeedState,
                       appearance: MenuBarAppearance = MenuBarAppearance()) {
        button.image = image(state: state, appearance: appearance)
        // 让 variableLength 跟随新图像尺寸，边距交给系统，避免固定长度重复预留空间。
        button.invalidateIntrinsicContentSize()
        let detail = appearance.mode.showsSpeed ? description(state) : "NetBar"
        button.toolTip = appearance.mode.showsSpeed
            ? "\(detail)\nWi-Fi / 以太网接口合计 · 点击查看应用明细"
            : "NetBar · 点击查看应用明细"
        button.setAccessibilityLabel("\(detail)，点击查看应用明细")
    }

    static func image(state: MenuBarSpeedState, appearance: MenuBarAppearance) -> NSImage {
        guard appearance.mode.showsSpeed else { return BrandIcon.statusBarImage() }
        let upload: String
        let download: String
        if case .available(let rate) = state {
            upload = MenuBarRate.string(rate.upload, compact: appearance.compactUnits,
                                        decimalPlaces: appearance.decimalPlaces)
            download = MenuBarRate.string(rate.download, compact: appearance.compactUnits,
                                          decimalPlaces: appearance.decimalPlaces)
        } else {
            upload = "—"
            download = "—"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(named: appearance.fontName, size: appearance.fontSize), .foregroundColor: NSColor.black
        ]
        func text(_ value: String) -> NSAttributedString {
            NSAttributedString(string: value, attributes: attributes)
        }
        let lines = [text(upload), text(download)]
        // 箭头使用系统字体，避免自定义数字字体缺少方向符号。
        let arrowAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.black
        ]
        let arrows = ["↑", "↓"].map { NSAttributedString(string: $0, attributes: arrowAttributes) }
        let iconWidth: CGFloat = appearance.mode.showsIcon ? (appearance.showsArrows ? 25 : 22) : 0
        let arrowWidth: CGFloat = appearance.showsArrows ? 10 : 0
        let places = (0...2).contains(appearance.decimalPlaces) ? appearance.decimalPlaces : 1
        let number = "999" + (places == 0 ? "" : "." + String(repeating: "9", count: places))
        let units = appearance.compactUnits ? ["K", "M", "G"] : ["KB/s", "MB/s", "GB/s"]
        // 测量完整样例，避免逐字符取整累加空白；单位之间切换不改变占位。
        let referenceWidth = units.map { text(number + " " + $0).size().width }.max() ?? 0
        let contentWidth = lines.map { $0.size().width }.max() ?? 0
        // 最高单位或自定义字体超出样例时容纳完整文字，两侧各留 1 pt。
        let textWidth = ceil(max(referenceWidth, text("—").size().width, contentWidth)) + 2
        let width = iconWidth + arrowWidth + textWidth
        // NSStatusBarButton 的原生标题基线针对单行；模板图像内排两行，避免顶行裁切。
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if appearance.mode.showsIcon {
                BrandIcon.drawMark(in: CGRect(x: 3.5, y: 3, width: 11, height: 16),
                                   context: context, color: CGColor(gray: 0, alpha: 1))
            }
            for (index, line) in lines.enumerated() {
                let rowY = CGFloat((1 - index) * 11)
                if appearance.showsArrows {
                    let arrow = arrows[index]
                    arrow.draw(at: NSPoint(x: iconWidth, y: rowY + (11 - arrow.size().height) / 2))
                }
                let glyphLine = CTLineCreateWithAttributedString(line)
                let bounds = CTLineGetBoundsWithOptions(glyphLine, .useGlyphPathBounds)
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: width - 1 - line.size().width,
                                               y: rowY + (11 - bounds.height) / 2 - bounds.minY)
                CTLineDraw(glyphLine, context)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(state)
        return image
    }

    static func font(named name: String, size: Double = 9) -> NSFont {
        let pointSize = MenuBarAppearance.fontSizeRange.contains(size) ? size : 9
        let chosen = NSFont(name: name, size: pointSize)
            ?? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .medium)
        let sample = NSAttributedString(string: "0123456789.KMGB/s—", attributes: [.font: chosen])
        let bounds = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(sample), .useGlyphPathBounds)
        // 按可见字形而非字体行距适配，保留两行间的空隙，避免字号调大后被行距抵消。
        return bounds.height > 10
            ? NSFont(descriptor: chosen.fontDescriptor, size: pointSize * 10 / bounds.height) ?? chosen
            : chosen
    }

    private static func description(_ state: MenuBarSpeedState) -> String {
        switch state {
        case .available(let rate):
            return "上传 \(TrafficRate.string(rate.upload))，下载 \(TrafficRate.string(rate.download))"
        case .measuring: return "等待网速样本"
        case .unavailable: return "网卡统计暂不可用，将自动重试"
        }
    }
}
