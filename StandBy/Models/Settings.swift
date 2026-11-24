import SwiftUI

enum Defaults {
    static func get<T: Codable>(_ key: String, _ fallback: T) -> T {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: key), let v = try? JSONDecoder().decode(T.self, from: data) { return v }
        // 啟動參數覆寫（例如 -page 2 -clockStyle digital），方便測試與截圖。
        if let v = ud.object(forKey: key) as? T { return v }
        if let s = ud.string(forKey: key) {
            for text in [s, "\"\(s)\""] {
                if let v = try? JSONDecoder().decode(T.self, from: Data(text.utf8)) { return v }
            }
        }
        return fallback
    }

    static func set<T: Codable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

enum NightModeSetting: String, Codable, CaseIterable, Identifiable {
    case auto, on, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "自動"
        case .on: return "永遠開啟"
        case .off: return "關閉"
        }
    }
}

/// 一個時鐘樣式的一組配色。
struct ClockTint {
    var primary: Color     // 數字、主要刻度
    var secondary: Color   // 浮動時鐘的深色
    var minor: Color       // 分鐘刻度
    var hands: Color       // 時針、分針
    var accent: Color      // 秒針、鬧鐘圖示
    var day: Color         // 星期
    var swatch: Color      // 選色盤上顯示的顏色
}

enum ClockStyle: String, Codable, CaseIterable, Identifiable {
    case analog, digital, world, solar, float
    var id: String { rawValue }

    var title: String {
        switch self {
        case .analog: return "類比"
        case .digital: return "數字"
        case .world: return "世界"
        case .solar: return "太陽"
        case .float: return "浮動"
        }
    }

    var palette: [ClockTint] {
        switch self {
        case .analog:
            let classic = ClockTint(primary: .white, secondary: .white, minor: Color.white.opacity(0.4),
                                    hands: .white, accent: .sbOrange, day: .sbRed, swatch: .white)
            let hues: [UInt32] = [0xFF453A, 0xFF9F0A, 0xFFD60A, 0x30D158, 0x64D2FF, 0x0A84FF, 0xBF5AF2, 0xFF6482]
            return [classic] + hues.map { h in
                let c = Color(hex: h)
                return ClockTint(primary: c, secondary: c, minor: c.opacity(0.4), hands: c,
                                 accent: .white, day: c, swatch: c)
            }
        case .digital:
            let hues: [UInt32] = [0x7BA7F2, 0xF2F2F7, 0xFF5E57, 0xFF9F45, 0xFFD60A, 0x5FD35F,
                                  0x63E6BE, 0x64D2FF, 0x9D8CF5, 0xD08CF5, 0xFF7DAA]
            return hues.map { h in
                let c = Color(hex: h)
                let accent = h == 0xF2F2F7 ? Color.sbRed : c
                return ClockTint(primary: c, secondary: c, minor: c, hands: c, accent: accent, day: accent, swatch: c)
            }
        case .float:
            let pairs: [(UInt32, UInt32)] = [(0x67A0E6, 0x2B63B7), (0xFF8A80, 0xC7362F), (0xFFB45E, 0xC96A10),
                                             (0xFFE066, 0xB89400), (0x7FDC8A, 0x2E9B4A), (0x7BE3E0, 0x1C8C96),
                                             (0xB59BFF, 0x5E3FC4), (0xFF9AC8, 0xC83A7E), (0xE5E5EA, 0x7C7C84)]
            return pairs.map { p in
                ClockTint(primary: Color(hex: p.0), secondary: Color(hex: p.1), minor: .white, hands: .white,
                          accent: .sbRed, day: .white, swatch: Color(hex: p.0))
            }
        case .world, .solar:
            return [ClockTint(primary: .white, secondary: .white, minor: Color.white.opacity(0.4), hands: .white,
                              accent: .sbOrange, day: .sbRed, swatch: .white)]
        }
    }
}

struct WidgetItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WidgetKind
}

final class SettingsStore: ObservableObject {
    @Published var page: Int = Defaults.get("page", 0) { didSet { Defaults.set("page", page) } }
    @Published var clockStyle: ClockStyle = Defaults.get("clockStyle", ClockStyle.analog) { didSet { Defaults.set("clockStyle", clockStyle) } }
    @Published var clockColors: [String: Int] = Defaults.get("clockColors", [String: Int]()) { didSet { Defaults.set("clockColors", clockColors) } }
    @Published var stacks: [[WidgetItem]] = SettingsStore.loadStacks() { didSet { Defaults.set("stacks", stacks) } }
    @Published var stackIndex: [Int] = Defaults.get("stackIndex", [0, 0]) { didSet { Defaults.set("stackIndex", stackIndex) } }
    @Published var smartRotate: Bool = Defaults.get("smartRotate", true) { didSet { Defaults.set("smartRotate", smartRotate) } }
    @Published var widgetSuggestions: Bool = Defaults.get("widgetSuggestions", true) { didSet { Defaults.set("widgetSuggestions", widgetSuggestions) } }

    @Published var nightMode: NightModeSetting = Defaults.get("nightMode", NightModeSetting.auto) { didSet { Defaults.set("nightMode", nightMode) } }
    @Published var nightStart: Int = Defaults.get("nightStart", 22 * 60) { didSet { Defaults.set("nightStart", nightStart) } }
    @Published var nightEnd: Int = Defaults.get("nightEnd", 6 * 60) { didSet { Defaults.set("nightEnd", nightEnd) } }
    @Published var nightDimScreen: Bool = Defaults.get("nightDimScreen", false) { didSet { Defaults.set("nightDimScreen", nightDimScreen) } }
    @Published var nightSleep: Bool = Defaults.get("nightSleep", false) { didSet { Defaults.set("nightSleep", nightSleep) } }
    @Published var sleepAfter: Int = Defaults.get("sleepAfter", 120) { didSet { Defaults.set("sleepAfter", sleepAfter) } }

    @Published var alarmEnabled: Bool = Defaults.get("alarmEnabled", false) { didSet { Defaults.set("alarmEnabled", alarmEnabled) } }
    @Published var alarmMinutes: Int = Defaults.get("alarmMinutes", 7 * 60) { didSet { Defaults.set("alarmMinutes", alarmMinutes) } }

    @Published var fahrenheit: Bool = Defaults.get("fahrenheit", false) { didSet { Defaults.set("fahrenheit", fahrenheit) } }
    @Published var hasSeenWelcome: Bool = Defaults.get("hasSeenWelcome", false) { didSet { Defaults.set("hasSeenWelcome", hasSeenWelcome) } }
    @Published var hiddenAlbums: [String] = Defaults.get("hiddenAlbums", [String]()) { didSet { Defaults.set("hiddenAlbums", hiddenAlbums) } }

    static let defaultStacks: [[WidgetItem]] = [
        [WidgetItem(kind: .clockSquare), WidgetItem(kind: .calendarDate),
         WidgetItem(kind: .clockClassic), WidgetItem(kind: .alarmDigital)],
        [WidgetItem(kind: .weather), WidgetItem(kind: .calendarMonth),
         WidgetItem(kind: .upNext), WidgetItem(kind: .weatherHourly)],
    ]

    /// 讀取儲存的堆疊；已移除的小工具種類（例如舊版的「家庭」）會被略過，其他小工具保留。
    static func loadStacks() -> [[WidgetItem]] {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: "stacks"),
           let raw = try? JSONDecoder().decode([[LossyWidgetItem]].self, from: data) {
            return raw.map { $0.compactMap(\.item) }
        }
        return Defaults.get("stacks", defaultStacks)
    }

    init() {
        if stacks.count < 2 { stacks = Self.defaultStacks }
        if stackIndex.count < 2 { stackIndex = [0, 0] }
    }

    var alarmText: String? { alarmEnabled ? Fmt.alarm(minutes: alarmMinutes) : nil }

    func colorIndex(for style: ClockStyle) -> Int {
        min(clockColors[style.rawValue] ?? 0, max(style.palette.count - 1, 0))
    }

    func tint(for style: ClockStyle) -> ClockTint { style.palette[colorIndex(for: style)] }

    func setColor(_ i: Int, for style: ClockStyle) { clockColors[style.rawValue] = i }

    func resetStacks() {
        stacks = Self.defaultStacks.map { $0.map { WidgetItem(kind: $0.kind) } }
        stackIndex = [0, 0]
    }
}

private struct LossyWidgetItem: Decodable {
    let item: WidgetItem?
    init(from decoder: Decoder) throws { item = try? WidgetItem(from: decoder) }
}
