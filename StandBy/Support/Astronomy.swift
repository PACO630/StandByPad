import SwiftUI

/// 低精度太陽位置（NOAA 近似式），用於太陽時鐘的天空顏色與世界時鐘的晨昏線。
enum SolarMath {
    struct Params { let decl: Double; let ra: Double; let gmst: Double }

    static func params(_ date: Date) -> Params {
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * .pi / 180
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180
        let eps = (23.439 - 0.0000004 * n) * .pi / 180
        let decl = asin(sin(eps) * sin(lambda))
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda))
        let gmst = (280.46061837 + 360.98564736629 * n).truncatingRemainder(dividingBy: 360) * .pi / 180
        return Params(decl: decl, ra: ra, gmst: gmst)
    }

    static func normalize(_ deg: Double) -> Double {
        var v = deg.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 }
        if v < -180 { v += 360 }
        return v
    }

    /// 太陽直射點（緯度、經度，單位：度）。
    static func subsolar(_ date: Date) -> (lat: Double, lon: Double) {
        let p = params(date)
        return (p.decl * 180 / .pi, normalize((p.ra - p.gmst) * 180 / .pi))
    }

    /// 太陽高度角（度）與時角（弧度，-π…π，負值＝上午）。
    static func position(_ date: Date, lat: Double, lon: Double) -> (elevation: Double, hourAngle: Double) {
        let p = params(date)
        var H = p.gmst + lon * .pi / 180 - p.ra
        H = atan2(sin(H), cos(H))
        let phi = lat * .pi / 180
        let s = sin(phi) * sin(p.decl) + cos(phi) * cos(p.decl) * cos(H)
        return (asin(max(-1, min(1, s))) * 180 / .pi, H)
    }
}

enum SkyPalette {
    struct Sky {
        let top: Color
        let bottom: Color
        let glow: Color
        let glowPoint: UnitPoint
        let textOpacity: Double
    }

    /// (太陽高度, 上方, 下方, 光暈)
    private static let keys: [(Double, RGB, RGB, RGB)] = [
        (-18, RGB(0x060A1C), RGB(0x111833), RGB(0x1F2850)),
        (-8, RGB(0x17224D), RGB(0x4F3F70), RGB(0x9A5E7A)),
        (-2, RGB(0x3A5894), RGB(0xD98466), RGB(0xFFAE78)),
        (6, RGB(0x6A99CB), RGB(0xC29F7C), RGB(0xFFD69E)),
        (20, RGB(0x7DB9EF), RGB(0x9A967F), RGB(0xD4ECFF)),
        (45, RGB(0x5DAEF7), RGB(0x9CCBF0), RGB(0xEAF6FF)),
    ]

    static func sky(date: Date, lat: Double, lon: Double) -> Sky {
        let pos = SolarMath.position(date, lat: lat, lon: lon)
        let e = pos.elevation
        var top = keys[0].1, bottom = keys[0].2, glow = keys[0].3
        if e >= keys[keys.count - 1].0 {
            let k = keys[keys.count - 1]
            top = k.1; bottom = k.2; glow = k.3
        } else if e > keys[0].0 {
            for i in 0..<(keys.count - 1) where e >= keys[i].0 && e < keys[i + 1].0 {
                let t = (e - keys[i].0) / (keys[i + 1].0 - keys[i].0)
                top = keys[i].1.mix(keys[i + 1].1, t)
                bottom = keys[i].2.mix(keys[i + 1].2, t)
                glow = keys[i].3.mix(keys[i + 1].3, t)
            }
        }
        let x = 0.5 + 0.42 * sin(pos.hourAngle)
        let y = 1.0 - min(max((e + 12) / 70, 0), 1) * 0.92
        let textOpacity = e < -6 ? 0.42 : 0.55
        return Sky(top: top.color, bottom: bottom.color, glow: glow.color,
                   glowPoint: UnitPoint(x: x, y: y), textOpacity: textOpacity)
    }
}
