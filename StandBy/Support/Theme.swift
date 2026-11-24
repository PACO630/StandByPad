import SwiftUI
import UIKit

/// 以 `-demo` 啟動參數執行時，會填入示範用的音樂、家庭與天氣資料（方便在模擬器截圖）。
enum Demo {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-demo")

    static func artwork(hue: Double? = nil) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors: [CGColor]
            if let hue {
                colors = [UIColor(hue: hue, saturation: 0.45, brightness: 0.7, alpha: 1).cgColor,
                          UIColor(hue: fmod(hue + 0.08, 1), saturation: 0.2, brightness: 0.95, alpha: 1).cgColor]
            } else {
                colors = [UIColor(red: 0.62, green: 0.55, blue: 0.78, alpha: 1).cgColor,
                          UIColor(red: 0.93, green: 0.82, blue: 0.88, alpha: 1).cgColor]
            }
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 600, y: 600), options: [])
            UIColor.white.withAlphaComponent(0.55).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 330, y: 80, width: 180, height: 180))
            UIColor(red: 0.35, green: 0.3, blue: 0.5, alpha: 0.6).setFill()
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 0, y: 470))
            p.addCurve(to: CGPoint(x: 600, y: 420), controlPoint1: CGPoint(x: 180, y: 330), controlPoint2: CGPoint(x: 380, y: 560))
            p.addLine(to: CGPoint(x: 600, y: 600)); p.addLine(to: CGPoint(x: 0, y: 600)); p.close(); p.fill()
        }
    }
}

/// 除錯用：`-ui editWidgets|gallery|editClock|palette|editPhotos|music|settings` 直接開到指定狀態。
enum DebugLaunch {
    static var state: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "ui")
        #else
        return nil
        #endif
    }
}

// MARK: - Colors

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    static let sbGray = Color(hex: 0x8E8E93)
    static let sbCard = Color(hex: 0x1C1C1E)
    static let sbFill = Color(hex: 0x2C2C2E)
    static let sbButton = Color(hex: 0x3A3A3C)
    static let sbOrange = Color(hex: 0xFF9F0A)
    static let sbRed = Color(hex: 0xFF453A)
    static let sbBlue = Color(hex: 0x0A84FF)
    static let sbGreen = Color(hex: 0x30D158)
    /// 夜間模式的單色紅。
    static let nightRed = Color(.sRGB, red: 1.0, green: 0.07, blue: 0.05, opacity: 1)
}

struct RGB: Equatable {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

// MARK: - Geometry helpers

extension CGPoint {
    static func + (l: CGPoint, r: CGVector) -> CGPoint { CGPoint(x: l.x + r.dx, y: l.y + r.dy) }
    static func - (l: CGPoint, r: CGVector) -> CGPoint { CGPoint(x: l.x - r.dx, y: l.y - r.dy) }
}

extension CGVector {
    static func * (l: CGVector, r: CGFloat) -> CGVector { CGVector(dx: l.dx * r, dy: l.dy * r) }
    /// 0 = 12 點方向，順時針。
    static func clock(_ fraction: Double) -> CGVector {
        let a = fraction * 2 * Double.pi
        return CGVector(dx: sin(a), dy: -cos(a))
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Formatting

enum Fmt {
    static let locale: Locale = Locale(identifier: Locale.preferredLanguages.first ?? "zh-Hant-TW")
    static var isChinese: Bool { locale.identifier.hasPrefix("zh") }

    private static var cache: [String: DateFormatter] = [:]

    static func string(_ date: Date, _ template: String, tz: TimeZone = .current) -> String {
        let key = "\(template)|\(tz.identifier)"
        if let f = cache[key] { return f.string(from: date) }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate(template)
        cache[key] = f
        return f.string(from: date)
    }

    static var uses24h: Bool {
        let f = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return !f.contains("a")
    }

    /// 待機模式的大時鐘不顯示上午／下午，也不補零小時。
    static func clockParts(_ date: Date, tz: TimeZone = .current) -> (hour: String, minute: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: date)
        var h = c.hour ?? 0
        if !uses24h { h %= 12; if h == 0 { h = 12 } }
        return (String(h), String(format: "%02d", c.minute ?? 0))
    }

    static func clock(_ date: Date, tz: TimeZone = .current) -> String {
        let p = clockParts(date, tz: tz)
        return "\(p.hour):\(p.minute)"
    }

    static func weekdayShort(_ d: Date) -> String {
        isChinese ? string(d, "EEE") : string(d, "EEE").uppercased()
    }
    static func weekdayLong(_ d: Date) -> String { string(d, "EEEE") }
    static func day(_ d: Date) -> String { String(Calendar.current.component(.day, from: d)) }
    static func monthYear(_ d: Date) -> String { string(d, "yMMMM") }
    static func monthName(_ d: Date) -> String {
        isChinese ? string(d, "LLLL") : string(d, "LLLL").uppercased()
    }
    static func fullDate(_ d: Date) -> String { string(d, "yMMMd") }
    static func time(_ d: Date, tz: TimeZone = .current) -> String { string(d, "jmm", tz: tz) }
    static func hourLabel(_ d: Date) -> String { isChinese ? string(d, "H") : string(d, "ha") }

    static func alarm(minutes: Int) -> String {
        let d = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return time(d)
    }

    static func temp(_ c: Double?, fahrenheit: Bool, unit: Bool = false) -> String {
        guard let c else { return "--°" }
        let v = fahrenheit ? c * 9 / 5 + 32 : c
        return "\(Int(v.rounded()))°" + (unit ? (fahrenheit ? "F" : "C") : "")
    }
}

// MARK: - Shared controls

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .hoverEffect(.highlight)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CapsuleButton: View {
    var title: String? = nil
    var systemImage: String? = nil
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title).font(.system(size: 19, weight: .semibold))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 20, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .frame(minWidth: 84, minHeight: 44)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.white.opacity(0.2)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label ?? title ?? "")
    }
}

/// 編輯模式最上方的列：左側自訂、中間標題、右側「設定」與「完成」。
struct EditTopBar<Leading: View>: View {
    let title: String?
    let onSettings: () -> Void
    let onDone: () -> Void
    let leading: Leading

    init(title: String? = nil, onSettings: @escaping () -> Void, onDone: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.onSettings = onSettings
        self.onDone = onDone
        self.leading = leading()
    }

    var body: some View {
        ZStack {
            if let title {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            HStack(spacing: 12) {
                leading
                Spacer()
                CapsuleButton(systemImage: "gearshape.fill", label: "設定", action: onSettings)
                CapsuleButton(title: "完成", action: onDone)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 30)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct PermissionPrompt: View {
    let symbol: String
    let title: String
    let message: String
    let button: String
    var scale: CGFloat = 1
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 54 * scale, weight: .regular))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 26 * scale, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 17 * scale))
                .foregroundColor(.sbGray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440 * scale)
            Button(action: action) {
                Text(button)
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22 * scale)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 6 * scale)
        }
        .padding(24 * scale)
    }
}

enum SystemLinks {
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
    static func open(_ s: String) {
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }
}
