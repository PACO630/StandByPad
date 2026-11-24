import SwiftUI

enum WidgetApp: String, CaseIterable, Identifiable {
    case clock, calendar, weather, music, photos, batteries
    var id: String { rawValue }

    var name: String {
        switch self {
        case .clock: return "時鐘"
        case .calendar: return "行事曆"
        case .weather: return "天氣"
        case .music: return "音樂"
        case .photos: return "照片"
        case .batteries: return "電池"
        }
    }

    var kinds: [WidgetKind] { WidgetKind.allCases.filter { $0.app == self } }

    var buttonColor: Color {
        switch self {
        case .music: return Color(hex: 0xFA2D55)
        case .weather: return Color(hex: 0x1F7AE0)
        case .calendar: return .sbRed
        case .batteries: return .sbGreen
        default: return .white
        }
    }

    var buttonText: Color {
        switch self {
        case .music, .weather, .calendar: return .white
        default: return .black
        }
    }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clockSquare, clockClassic, alarmDigital, worldClocks
    case calendarDate, calendarMonth, upNext
    case weather, weatherHourly
    case music, photos, battery

    var id: String { rawValue }

    var app: WidgetApp {
        switch self {
        case .clockSquare, .clockClassic, .alarmDigital, .worldClocks: return .clock
        case .calendarDate, .calendarMonth, .upNext: return .calendar
        case .weather, .weatherHourly: return .weather
        case .music: return .music
        case .photos: return .photos
        case .battery: return .batteries
        }
    }

    var title: String {
        switch self {
        case .clockSquare: return "時鐘"
        case .clockClassic: return "經典時鐘"
        case .alarmDigital: return "數字時鐘"
        case .worldClocks: return "世界時鐘"
        case .calendarDate: return "日期"
        case .calendarMonth: return "月曆"
        case .upNext: return "即將到來"
        case .weather: return "目前天氣"
        case .weatherHourly: return "每小時預報"
        case .music: return "聆聽活動"
        case .photos: return "精選照片"
        case .battery: return "電池"
        }
    }

    var subtitle: String {
        switch self {
        case .clockSquare: return "從遠處也能看清楚目前的時間。"
        case .clockClassic: return "以經典錶盤查看時間。"
        case .alarmDigital: return "以大字體查看時間與下一個鬧鐘。"
        case .worldClocks: return "查看世界各地城市的時間。"
        case .calendarDate: return "查看今天的日期。"
        case .calendarMonth: return "一眼看完本月的日期。"
        case .upNext: return "查看接下來的行程。"
        case .weather: return "查看目前位置的天氣狀況。"
        case .weatherHourly: return "查看接下來幾小時的天氣變化。"
        case .music: return "查看目前播放的歌曲並快速取用最近播放的音樂。"
        case .photos: return "從你的照片圖庫中展示精選照片。"
        case .battery: return "查看裝置的電池電量。"
        }
    }
}

/// 小工具庫側邊欄用的 App 圖像（以 SF Symbols 繪製）。
struct AppIconView: View {
    let app: WidgetApp
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            switch app {
            case .clock:
                shape.fill(Color.black)
                Image(systemName: "clock").font(.system(size: size * 0.62, weight: .regular)).foregroundColor(.white)
            case .calendar:
                shape.fill(Color.white)
                VStack(spacing: -size * 0.04) {
                    Text(Fmt.weekdayShort(Date())).font(.system(size: size * 0.18, weight: .semibold)).foregroundColor(.sbRed)
                    Text(Fmt.day(Date())).font(.system(size: size * 0.46, weight: .regular)).foregroundColor(.black)
                }
            case .weather:
                shape.fill(LinearGradient(colors: [Color(hex: 0x2A7FE0), Color(hex: 0x74B9F5)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: size * 0.5))
            case .music:
                shape.fill(LinearGradient(colors: [Color(hex: 0xFC5C7D), Color(hex: 0xFA233B)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "music.note").font(.system(size: size * 0.5, weight: .semibold)).foregroundColor(.white)
            case .photos:
                shape.fill(Color.white)
                Image(systemName: "camera.macro")
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(AngularGradient(colors: [.orange, .yellow, .green, .cyan, .blue, .purple, .pink, .orange], center: .center))
            case .batteries:
                shape.fill(LinearGradient(colors: [Color(hex: 0x34C759), Color(hex: 0x248A3D)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "battery.100").font(.system(size: size * 0.42, weight: .semibold)).foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 智慧型輪替：依時間與情境，挑出目前最相關的小工具。
enum SmartRotation {
    struct Context {
        var now: Date
        var musicPlaying: Bool
        var nextEvent: Date?
        var batteryLow: Bool
    }

    static func score(_ k: WidgetKind, _ c: Context) -> Int {
        let h = Calendar.current.component(.hour, from: c.now)
        switch k {
        case .music: return c.musicPlaying ? 100 : 0
        case .upNext:
            if let e = c.nextEvent, e.timeIntervalSince(c.now) < 3600, e.timeIntervalSince(c.now) > -600 { return 90 }
            return 10
        case .battery: return c.batteryLow ? 80 : 5
        case .weather, .weatherHourly:
            if (6..<10).contains(h) { return 60 }
            if (16..<19).contains(h) { return 40 }
            return 20
        case .alarmDigital: return (h >= 21 || h < 6) ? 55 : 10
        case .calendarDate, .calendarMonth: return (8..<21).contains(h) ? 30 : 15
        case .clockSquare, .clockClassic: return 25
        case .photos: return 22
        case .worldClocks: return 12
        }
    }
}
