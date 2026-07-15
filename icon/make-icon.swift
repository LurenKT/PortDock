// 生成 PortDock 图标：深海军蓝渐变圆角矩形 + 白色船锚。
// 用法: swift icon/make-icon.swift  （输出 icon/AppIcon-1024.png，精确 1024px）
import AppKit

let px = 1024
let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 图标网格：1024 画布内 824×824 圆角矩形
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(
  starting: NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.55, alpha: 1),
  ending: NSColor(calibratedRed: 0.03, green: 0.10, blue: 0.19, alpha: 1))!
gradient.draw(in: squircle, angle: -90)

// 锚（描边风格，圆头线帽）
let glyph = NSBezierPath()
glyph.lineWidth = 40
glyph.lineCapStyle = .round
// 顶环
glyph.appendOval(in: NSRect(x: 512 - 52, y: 668, width: 104, height: 104))
// 锚杆
glyph.move(to: NSPoint(x: 512, y: 668))
glyph.line(to: NSPoint(x: 512, y: 306))
// 横杆
glyph.move(to: NSPoint(x: 398, y: 592))
glyph.line(to: NSPoint(x: 626, y: 592))
// 底部锚臂：圆弧经过底点(512,306)，先 move 到弧起点避免连线
let c = NSPoint(x: 512, y: 566), r: CGFloat = 260
func onArc(_ deg: CGFloat) -> NSPoint {
  NSPoint(x: c.x + r * cos(deg * .pi / 180), y: c.y + r * sin(deg * .pi / 180))
}
glyph.move(to: onArc(200))
glyph.appendArc(withCenter: c, radius: r, startAngle: 200, endAngle: 340, clockwise: false)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 18
shadow.set()
NSColor.white.setStroke()
glyph.stroke()

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "icon/AppIcon-1024.png"))
print("写出 icon/AppIcon-1024.png (\(rep.pixelsWide)px)")
