import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 以左上為原點
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((h>>16)&255)/255, CGFloat((h>>8)&255)/255, CGFloat(h&255)/255, a])!
}
func lin(_ colors: [CGColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func rad(_ colors: [CGColor], _ locs: [CGFloat], c: CGPoint, r: CGFloat) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [.drawsBeforeStartLocation])
}

// 1. 背景：深夜藍到近黑，像床頭的夜色
lin([rgb(0x1B2238), rgb(0x0B0E18), rgb(0x040508)], [0, 0.55, 1], from: CGPoint(x: S/2, y: 0), to: CGPoint(x: S/2, y: S))
// 下方暖色光暈：充電座的光
rad([rgb(0xFF9F0A, 0.16), rgb(0xFF9F0A, 0)], [0, 1], c: CGPoint(x: S/2, y: S*1.02), r: S*0.62)

let c = CGPoint(x: S/2, y: S/2)
// 2. 錶盤底板：圓角方形（待機模式的刻度形狀），玻璃般的層次
func squircle(_ a: CGFloat, n: CGFloat = 4.6, steps: Int = 720) -> CGPath {
    let p = CGMutablePath()
    for i in 0...steps {
        let t = Double(i)/Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = CGFloat(copysign(pow(abs(ct), 2/Double(n)), ct)) * a
        let y = CGFloat(copysign(pow(abs(st), 2/Double(n)), st)) * a
        let pt = CGPoint(x: c.x + x, y: c.y + y)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath(); return p
}
let plateA: CGFloat = 352
// 底板陰影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 22), blur: 60, color: rgb(0x000000, 0.75))
ctx.addPath(squircle(plateA)); ctx.setFillColor(rgb(0x14161F)); ctx.fillPath()
ctx.restoreGState()
// 底板漸層
ctx.saveGState(); ctx.addPath(squircle(plateA)); ctx.clip()
lin([rgb(0x262A38), rgb(0x12141C), rgb(0x0A0B10)], [0, 0.5, 1], from: CGPoint(x: S/2, y: c.y - plateA), to: CGPoint(x: S/2, y: c.y + plateA))
rad([rgb(0x5B6BA8, 0.22), rgb(0x5B6BA8, 0)], [0, 1], c: CGPoint(x: c.x, y: c.y - plateA*0.55), r: plateA*1.1)
ctx.restoreGState()
// 頂部高光邊
ctx.saveGState(); ctx.addPath(squircle(plateA)); ctx.clip()
ctx.addPath(squircle(plateA - 2)); ctx.setLineWidth(5)
ctx.replacePathWithStrokedPath(); ctx.clip()
lin([rgb(0xFFFFFF, 0.38), rgb(0xFFFFFF, 0.04), rgb(0xFFFFFF, 0.10)], [0, 0.5, 1], from: CGPoint(x: S/2, y: c.y - plateA), to: CGPoint(x: S/2, y: c.y + plateA))
ctx.restoreGState()

// 3. 刻度：沿圓角方形分布
let a: CGFloat = 300, n: Double = 4.6
for i in 0..<60 {
    let th = Double(i)/60 * 2 * .pi
    let dx = CGFloat(sin(th)), dy = CGFloat(-cos(th))
    let r = a / CGFloat(pow(pow(abs(Double(dx)), n) + pow(abs(Double(dy)), n), 1/n))
    let hour = i % 5 == 0
    let len: CGFloat = hour ? 44 : 20
    ctx.setLineCap(.round)
    ctx.setLineWidth(hour ? 13 : 6)
    ctx.setStrokeColor(hour ? rgb(0xF5F5F7) : rgb(0xF5F5F7, 0.32))
    ctx.move(to: CGPoint(x: c.x + dx*(r-len), y: c.y + dy*(r-len)))
    ctx.addLine(to: CGPoint(x: c.x + dx*r, y: c.y + dy*r))
    ctx.strokePath()
}

// 4. 指針：10:09（細頸 + 圓頭粗身），帶柔和陰影
func dir(_ f: Double) -> CGVector { CGVector(dx: sin(f * 2 * Double.pi), dy: -cos(f * 2 * Double.pi)) }
func hand(_ f: Double, len: CGFloat, w: CGFloat) {
    let d = dir(f)
    ctx.setLineCap(.round); ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(w*0.42)
    ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + d.dx*40, y: c.y + d.dy*40)); ctx.strokePath()
    ctx.setLineWidth(w)
    ctx.move(to: CGPoint(x: c.x + d.dx*40, y: c.y + d.dy*40)); ctx.addLine(to: CGPoint(x: c.x + d.dx*len, y: c.y + d.dy*len)); ctx.strokePath()
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0x000000, 0.6))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
let mins = 9.0 + 34.0/60, hrs = 10.0 + mins/60
hand(hrs/12, len: 170, w: 34)
hand(mins/60, len: 262, w: 34)
ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: c.x-24, y: c.y-24, width: 48, height: 48))
// 秒針（橘色）指向約 7 點方向
let sd = dir(34.0/60)
ctx.setStrokeColor(rgb(0xFF9F0A)); ctx.setLineWidth(9); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: c.x - sd.dx*62, y: c.y - sd.dy*62)); ctx.addLine(to: CGPoint(x: c.x + sd.dx*290, y: c.y + sd.dy*290)); ctx.strokePath()
ctx.setFillColor(rgb(0xFF9F0A)); ctx.fillEllipse(in: CGRect(x: c.x-17, y: c.y-17, width: 34, height: 34))
ctx.setFillColor(rgb(0x0B0C11)); ctx.fillEllipse(in: CGRect(x: c.x-7, y: c.y-7, width: 14, height: 14))
ctx.endTransparencyLayer()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
