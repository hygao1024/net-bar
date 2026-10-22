import AppKit

/// 已确认的双流线标记；应用资源和菜单栏共用路径，避免缩放位图造成模糊。
enum BrandIcon {
    static func drawMark(in rect: CGRect, context: CGContext, color: CGColor) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 260, y: rect.height / 500)
        context.setFillColor(color)
        for offset in [CGPoint.zero, CGPoint(x: 160, y: 125)] {
            context.saveGState()
            context.translateBy(x: offset.x, y: offset.y)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 50))
            path.addCurve(to: CGPoint(x: 100, y: 50), control1: CGPoint(x: 0, y: -17), control2: CGPoint(x: 100, y: -17))
            path.addLine(to: CGPoint(x: 100, y: 353))
            path.addCurve(to: CGPoint(x: 69, y: 370), control1: CGPoint(x: 100, y: 373), control2: CGPoint(x: 83, y: 383))
            path.addLine(to: CGPoint(x: 9, y: 314))
            path.addQuadCurve(to: CGPoint(x: 0, y: 293), control: CGPoint(x: 0, y: 306))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    static func drawAppIcon(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
        // 透明外边距适配 macOS 应用图标的视觉尺寸。
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 185, cornerHeight: 185, transform: nil)
        context.addPath(tile)
        context.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [CGColor(red: 0.02, green: 0.36, blue: 1, alpha: 1),
                     CGColor(red: 0.03, green: 0.62, blue: 0.98, alpha: 1)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100),
                                   end: CGPoint(x: 512, y: 924), options: [])
        drawMark(in: CGRect(x: 382, y: 262, width: 260, height: 500), context: context,
                 color: CGColor(gray: 1, alpha: 1))
        context.restoreGState()
    }

    static func statusBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // 小尺寸略加宽笔画，顶部与底部各保留 1 pt 空间。
            drawMark(in: CGRect(x: 3.5, y: 1, width: 11, height: 16), context: context,
                     color: CGColor(gray: 0, alpha: 1))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "应用网速"
        return image
    }
}
