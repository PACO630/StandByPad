import SwiftUI

/// 繪製 Apple 風格的指針：細頸 + 圓頭粗身、橘色秒針含尾端與中心圈。
enum HandsPainter {
    struct Style {
        var hour: CGFloat = 0.5
        var minute: CGFloat = 0.82
        var second: CGFloat = 0.9
        var width: CGFloat = 0.068
        var color: Color = .white
        var secondColor: Color = .sbOrange
        var showSeconds = true
    }

    static func draw(_ g: inout GraphicsContext, center c: CGPoint, radius R: CGFloat, date: Date,
                     tz: TimeZone = .current, style s: Style) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let sec = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1e9
        let mins = Double(comps.minute ?? 0) + sec / 60
        let hrs = Double((comps.hour ?? 0) % 12) + mins / 60
        let neck = R * 0.1

        func hand(_ fraction: Double, _ length: CGFloat) {
            let d = CGVector.clock(fraction)
            var thin = Path()
            thin.move(to: c)
            thin.addLine(to: c + d * neck)
            g.stroke(thin, with: .color(s.color), style: StrokeStyle(lineWidth: R * s.width * 0.42, lineCap: .round))
            var thick = Path()
            thick.move(to: c + d * neck)
            thick.addLine(to: c + d * (R * length))
            g.stroke(thick, with: .color(s.color), style: StrokeStyle(lineWidth: R * s.width, lineCap: .round))
        }

        hand(hrs / 12, s.hour)
        hand(mins / 60, s.minute)
        let capR = R * s.width * 0.72
        g.fill(Path(ellipseIn: CGRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)), with: .color(s.color))

        if s.showSeconds {
            let d = CGVector.clock(sec / 60)
            var p = Path()
            p.move(to: c - d * (R * 0.16))
            p.addLine(to: c + d * (R * s.second))
            g.stroke(p, with: .color(s.secondColor), style: StrokeStyle(lineWidth: max(1, R * 0.016), lineCap: .round))
            let r1 = R * 0.042, r2 = R * 0.018
            g.fill(Path(ellipseIn: CGRect(x: c.x - r1, y: c.y - r1, width: r1 * 2, height: r1 * 2)), with: .color(s.secondColor))
            g.fill(Path(ellipseIn: CGRect(x: c.x - r2, y: c.y - r2, width: r2 * 2, height: r2 * 2)), with: .color(.black))
        }
    }
}

/// 小工具用的錶盤。exponent = 2 為圓形；約 4–5 為待機模式的圓角方形刻度。
struct AnalogDial: View {
    var exponent: CGFloat = 2
    var numerals: [Int] = []
    var tint: Color = .white
    var minorTint: Color = Color.white.opacity(0.4)
    var secondColor: Color = .sbOrange
    var handColor: Color = .white
    var face: Color? = nil
    var timeZone: TimeZone = .current
    var minuteTicks = true
    var smooth = true
    var numeralScale: CGFloat = 0.24
    var numeralInset: CGFloat = 0.3

    var body: some View {
        TimelineView(.animation(minimumInterval: smooth ? 1.0 / 30 : 1, paused: false)) { ctx in
            Canvas { g, size in draw(&g, size: size, date: ctx.date) }
        }
        .accessibilityElement()
        .accessibilityLabel("時鐘")
    }

    private func radius(_ d: CGVector, _ a: CGFloat) -> CGFloat {
        a / pow(pow(abs(d.dx), exponent) + pow(abs(d.dy), exponent), 1 / exponent)
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, date: Date) {
        let R = min(size.width, size.height) / 2
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        if let face {
            g.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)), with: .color(face))
        }
        let a = R * (face == nil ? 0.97 : 0.9)
        for i in 0..<60 {
            let isHour = i % 5 == 0
            if !isHour && !minuteTicks { continue }
            let d = CGVector.clock(Double(i) / 60)
            let r = radius(d, a)
            let len = isHour ? R * 0.12 : R * 0.055
            var p = Path()
            p.move(to: c + d * (r - len))
            p.addLine(to: c + d * r)
            g.stroke(p, with: .color(isHour ? tint : minorTint),
                     style: StrokeStyle(lineWidth: isHour ? R * 0.022 : R * 0.011, lineCap: .round))
        }
        for n in numerals {
            let d = CGVector.clock(Double(n % 12) / 12)
            let r = radius(d, a)
            let text = g.resolve(Text("\(n)").font(.system(size: R * numeralScale, weight: .semibold)).foregroundColor(tint))
            g.draw(text, at: c + d * (r - R * numeralInset), anchor: .center)
        }
        HandsPainter.draw(&g, center: c, radius: R, date: date, tz: timeZone,
                          style: .init(color: handColor, secondColor: secondColor))
    }
}

/// 全螢幕「類比」時鐘：刻度從中心放射到螢幕邊緣，12/3/6/9 使用寬體數字。
struct AnalogFullClock: View {
    let tint: ClockTint
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
                    Canvas { g, size in Self.draw(&g, size: size, date: ctx.date, tint: tint) }
                }
                TimelineView(.everyMinute) { ctx in
                    ZStack {
                        if let alarm = settings.alarmText {
                            HStack(spacing: H * 0.012) {
                                Image(systemName: "alarm.fill").foregroundColor(tint.accent)
                                Text(alarm).foregroundColor(.white)
                            }
                            .position(x: W / 2 - W * 0.155, y: H / 2)
                        }
                        HStack(spacing: H * 0.012) {
                            Text(Fmt.weekdayShort(ctx.date)).foregroundColor(tint.day)
                            Text(Fmt.day(ctx.date)).foregroundColor(.white)
                        }
                        .position(x: W / 2 + W * 0.155, y: H / 2)
                    }
                    .font(.system(size: H * 0.052, weight: .semibold))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("類比時鐘")
    }

    static func draw(_ g: inout GraphicsContext, size: CGSize, date: Date, tint: ClockTint) {
        let W = size.width, H = size.height
        let c = CGPoint(x: W / 2, y: H / 2)
        let m = H * 0.045
        let a = W / 2 - m, b = H / 2 - m
        for i in 0..<60 {
            let d = CGVector.clock(Double(i) / 60)
            let tx = abs(d.dx) > 1e-6 ? a / abs(d.dx) : .greatestFiniteMagnitude
            let ty = abs(d.dy) > 1e-6 ? b / abs(d.dy) : .greatestFiniteMagnitude
            let t = min(tx, ty)
            var p = Path()
            if i % 15 == 0 {
                p.move(to: c + d * (t - H * 0.065))
                p.addLine(to: c + d * t)
                g.stroke(p, with: .color(tint.primary), style: StrokeStyle(lineWidth: H * 0.008, lineCap: .round))
                let n = i == 0 ? 12 : i / 5
                let text = g.resolve(Text("\(n)").font(.system(size: H * 0.17, weight: .semibold).width(.expanded)).foregroundColor(tint.primary))
                g.draw(text, at: c + d * (t - H * 0.2), anchor: .center)
            } else if i % 5 == 0 {
                p.move(to: c + d * (t - H * 0.3))
                p.addLine(to: c + d * (t - H * 0.012))
                g.stroke(p, with: .color(tint.primary.opacity(0.82)), style: StrokeStyle(lineWidth: H * 0.009, lineCap: .round))
            } else {
                p.move(to: c + d * (t - H * 0.042))
                p.addLine(to: c + d * t)
                g.stroke(p, with: .color(tint.minor), style: StrokeStyle(lineWidth: H * 0.005, lineCap: .round))
            }
        }
        HandsPainter.draw(&g, center: c, radius: H / 2, date: date,
                          style: .init(hour: 0.5, minute: 0.86, second: 0.92, width: 0.07,
                                       color: tint.hands, secondColor: tint.accent))
    }
}
