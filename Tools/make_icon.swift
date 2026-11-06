// Vẽ icon app (3 biến thể cho iOS 18/26: mặc định, tối, phủ màu):
//   swift Tools/make_icon.swift <out.png> [light|dark|tinted]
// Chạy Tools/make_icons.sh để tạo cả 3 vào AppIcon.appiconset.
import AppKit
import CoreImage

let out = CommandLine.arguments[1]
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let tinted = mode == "tinted"
let size = 1024.0

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let full = NSRect(x: 0, y: 0, width: size, height: size)

switch mode {
case "dark":
    break // nền trong suốt: iOS tự đặt nền tối
case "tinted":
    NSColor.black.setFill(); full.fill() // ảnh xám trên nền đen: iOS tự phủ màu theo độ sáng
default:
    // Nền sáng giống ô Control Center
    NSGradient(colors: [NSColor(white: 1.0, alpha: 1), NSColor(white: 0.93, alpha: 1)])!.draw(in: full, angle: -90)
}

let green = tinted ? NSColor(white: 0.92, alpha: 1) : NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1) // #34C759
let greenDark = tinted ? NSColor(white: 0.62, alpha: 1) : NSColor(red: 0.15, green: 0.66, blue: 0.29, alpha: 1)

// Màn hình (toạ độ gốc ở dưới-trái)
let screen = NSRect(x: 152, y: 330, width: 720, height: 480)
let screenPath = NSBezierPath(roundedRect: screen, xRadius: 64, yRadius: 64)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 30
shadow.set()
green.setFill()
screenPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [green.blended(withFraction: 0.12, of: .white)!, greenDark])!.draw(in: screenPath, angle: -90)

// Chân đế: cổ + đế
greenDark.setFill()
let neck = NSBezierPath()
neck.move(to: NSPoint(x: 452, y: 332))
neck.line(to: NSPoint(x: 572, y: 332))
neck.line(to: NSPoint(x: 592, y: 236))
neck.line(to: NSPoint(x: 432, y: 236))
neck.close()
neck.fill()
green.setFill()
NSBezierPath(roundedRect: NSRect(x: 352, y: 206, width: 320, height: 48), xRadius: 24, yRadius: 24).fill()

// Biểu tượng nút nguồn (tự vẽ, nét đều, đầu tròn) ở giữa màn hình
let center = NSPoint(x: screen.midX, y: screen.midY - 6)
let radius = screen.height * 0.27
let power = NSBezierPath()
// vòng cung hở ở phía trên (từ 120° đi ngược chiều kim đồng hồ tới 60°)
power.appendArc(withCenter: center, radius: radius, startAngle: 118, endAngle: 62, clockwise: false)
// vạch dọc
power.move(to: NSPoint(x: center.x, y: center.y + radius * 0.12))
power.line(to: NSPoint(x: center.x, y: center.y + radius * 1.18))
power.lineWidth = radius * 0.24
power.lineCapStyle = .round
power.lineJoinStyle = .round
(tinted ? NSColor.black : NSColor.white).setStroke()
power.stroke()

NSGraphicsContext.current = nil
let ci = CIImage(bitmapImageRep: rep)!
try! CIContext().writePNGRepresentation(of: ci, to: URL(fileURLWithPath: out), format: mode == "dark" ? .RGBA8 : .RGBX8,
                                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
