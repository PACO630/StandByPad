import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((h>>16)&255)/255, CGFloat((h>>8)&255)/255, CGFloat(h&255)/255, a])!
}
func newCtx() -> CGContext {
    let c = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.translateBy(x: 0, y: S); c.scaleBy(x: 1, y: -1)
    return c
}
func save(_ c: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func dir(_ f: Double) -> CGVector { CGVector(dx: sin(f * 2 * Double.pi), dy: -cos(f * 2 * Double.pi)) }
func line(_ c: CGContext, _ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ col: CGColor) {
    c.setLineCap(.round); c.setLineWidth(w); c.setStrokeColor(col)
    c.move(to: a); c.addLine(to: b); c.strokePath()
}
func pt(_ c: CGPoint, _ d: CGVector, _ r: CGFloat) -> CGPoint { CGPoint(x: c.x + d.dx * r, y: c.y + d.dy * r) }
let center = CGPoint(x: S/2, y: S/2)
let out = CommandLine.arguments[1]

// 1. 夜間紅：黑底、紅色圓角方形刻度與指針（待機模式的夜間模式）
do {
    let c = newCtx()
    c.setFillColor(rgb(0x000000)); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
    let red = rgb(0xFF3B30), dim = rgb(0x7A1C17)
    let a: CGFloat = 370, n = 4.6
    for i in 0..<60 {
        let d = dir(Double(i)/60)
        let r = a / CGFloat(pow(pow(abs(Double(d.dx)), n) + pow(abs(Double(d.dy)), n), 1/n))
        let hour = i % 5 == 0
        line(c, pt(center, d, r - (hour ? 62 : 26)), pt(center, d, r), hour ? 20 : 9, hour ? red : dim)
    }
    let m = 9.0/60, h = (10.0 + 9.0/60)/12
    for (f, len) in [(h, 190.0), (m, 290.0)] {
        let d = dir(f)
        line(c, center, pt(center, d, 46), 18, red)
        line(c, pt(center, d, 46), pt(center, d, CGFloat(len)), 42, red)
    }
    c.setFillColor(red); c.fillEllipse(in: CGRect(x: center.x-30, y: center.y-30, width: 60, height: 60))
    c.setFillColor(rgb(0x000000)); c.fillEllipse(in: CGRect(x: center.x-11, y: center.y-11, width: 22, height: 22))
    save(c, out + "/1.png")
}

// 2. 側躺的 iPad：橘底，橫放在支架上的裝置，螢幕上是時鐘和小工具
do {
    let c = newCtx()
    c.setFillColor(rgb(0xFF9F0A)); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
    // 床頭櫃桌面
    c.setFillColor(rgb(0x1C1C1E))
    // 橫放的裝置（底部靠在桌面上）
    let body = CGRect(x: 172, y: 297, width: 680, height: 430)
    c.addPath(CGPath(roundedRect: body, cornerWidth: 70, cornerHeight: 70, transform: nil)); c.fillPath()
    // 螢幕上的時鐘
    let cc = CGPoint(x: 360, y: 515), R: CGFloat = 128
    c.setFillColor(rgb(0xFFFFFF)); c.fillEllipse(in: CGRect(x: cc.x-R, y: cc.y-R, width: R*2, height: R*2))
    let dk = rgb(0x1C1C1E)
    line(c, cc, pt(cc, dir((10 + 9.0/60)/12), 68), 24, dk)
    line(c, cc, pt(cc, dir(9.0/60), 100), 24, dk)
    line(c, cc, pt(cc, dir(35.0/60), 108), 9, rgb(0xFF9F0A))
    c.setFillColor(rgb(0xFF9F0A)); c.fillEllipse(in: CGRect(x: cc.x-16, y: cc.y-16, width: 32, height: 32))
    // 螢幕上的小工具（三條資訊列）
    let wh = rgb(0xFFFFFF)
    for (i, w) in [(0, 200.0), (1, 150.0), (2, 110.0)] {
        let y = 425 + CGFloat(i) * 90
        c.setFillColor(i == 0 ? wh : rgb(0xFFFFFF, 0.55))
        c.addPath(CGPath(roundedRect: CGRect(x: 546, y: y, width: CGFloat(w), height: i == 0 ? 64 : 40), cornerWidth: 20, cornerHeight: 20, transform: nil)); c.fillPath()
    }
    save(c, out + "/2.png")
}

// 3. 浮動：黑底、兩個重疊的圓（浮動時鐘的數字配色），加兩顆冒號球
do {
    let c = newCtx()
    c.setFillColor(rgb(0x000000)); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
    let r1 = CGRect(x: 150, y: 250, width: 470, height: 470)
    let r2 = CGRect(x: 430, y: 330, width: 450, height: 450)
    c.setFillColor(rgb(0x67A0E6)); c.fillEllipse(in: r1)
    c.setFillColor(rgb(0x2B63B7)); c.fillEllipse(in: r2)
    // 重疊區域（平塗第三色）
    c.saveGState(); c.addEllipse(in: r1); c.clip()
    c.setFillColor(rgb(0x8CC6F7)); c.fillEllipse(in: r2)
    c.restoreGState()
    // 冒號球
    c.setFillColor(rgb(0xF2F2F7))
    c.fillEllipse(in: CGRect(x: 430, y: 300, width: 120, height: 120))
    c.fillEllipse(in: CGRect(x: 430, y: 560, width: 120, height: 120))
    save(c, out + "/3.png")
}

// 4. 月光時鐘：深藍底、米白新月，缺口處是時針與分針
do {
    let c = newCtx()
    let navy = rgb(0x1D2B53), cream = rgb(0xF6E7C1)
    c.setFillColor(navy); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
    let R: CGFloat = 330
    let moon = CGRect(x: center.x - R, y: center.y - R, width: R*2, height: R*2)
    let cut = moon.offsetBy(dx: 150, dy: -110)
    c.setFillColor(cream); c.fillEllipse(in: moon)
    c.setFillColor(navy); c.fillEllipse(in: cut)
    // 指針（在缺口的深色區域）
    let hc = CGPoint(x: cut.midX - 10, y: cut.midY + 20)
    line(c, hc, pt(hc, dir(0.0), 140), 32, cream)    // 分針
    line(c, hc, pt(hc, dir(0.25), 96), 32, cream)    // 時針（3:00）
    c.setFillColor(rgb(0xFF9F0A)); c.fillEllipse(in: CGRect(x: hc.x-24, y: hc.y-24, width: 48, height: 48))
    // 星星
    c.setFillColor(cream)
    for (x, y, r) in [(780.0, 760.0, 14.0), (840.0, 640.0, 9.0), (700.0, 850.0, 8.0)] {
        c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r*2, height: r*2))
    }
    save(c, out + "/4.png")
}
