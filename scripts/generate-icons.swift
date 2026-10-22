import AppKit

/// 与运行时共用 BrandIcon 的矢量路径，输出标准 macOS iconset。
@main
struct GenerateIcons {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
                    pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                BrandIcon.drawAppIcon(in: CGRect(x: 0, y: 0, width: pixels, height: pixels), context: context)
                let suffix = scale == 2 ? "@2x" : ""
                let data = bitmap.representation(using: .png, properties: [:])!
                try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
        try renderStatusPreview(to: output.deletingLastPathComponent().appendingPathComponent("status-icon-preview.png"))
        print("已生成应用图标：\(output.path)")
    }

    private static func renderStatusPreview(to url: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480,
            pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = graphics.cgContext
        for (index, dark) in [false, true].enumerated() {
            let x = CGFloat(index * 240)
            context.setFillColor(CGColor(gray: dark ? 0.12 : 0.96, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 240, height: 180))
            // 独立透明层中的 sourceIn 仅改变标记颜色，模拟系统模板着色。
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            for (size, y) in [(CGFloat(72), CGFloat(76)), (CGFloat(18), CGFloat(28))] {
                BrandIcon.statusBarImage().draw(in: CGRect(x: x + (240 - size) / 2, y: y, width: size, height: size))
            }
            if dark {
                context.setBlendMode(.sourceIn)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: x, y: 0, width: 240, height: 180))
                context.setBlendMode(.normal)
            }
            context.endTransparencyLayer()
        }
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
