import SwiftUI
import EventKit
import Photos

/// 所有小工具都以「邊長 100 單位」設計（u = side / 100），去背、放大，配合待機模式的遠距離閱讀。
struct WidgetView: View {
    let kind: WidgetKind
    let side: CGFloat

    var body: some View {
        let u = side / 100
        content(u)
            .frame(width: side, height: side)
    }

    @ViewBuilder private func content(_ u: CGFloat) -> some View {
        switch kind {
        case .clockSquare:
            AnalogDial(exponent: 4.4, numerals: [12, 3, 6, 9], numeralScale: 0.25, numeralInset: 0.3)
                .padding(u * 3)
        case .clockClassic:
            AnalogDial(exponent: 2, numerals: Array(1...12), numeralScale: 0.2, numeralInset: 0.27)
                .padding(u * 3)
        case .alarmDigital: AlarmDigitalWidget(u: u)
        case .worldClocks: WorldClocksWidget(u: u)
        case .calendarDate: CalendarDateWidget(u: u)
        case .calendarMonth: CalendarMonthWidget(u: u)
        case .upNext: UpNextWidget(u: u)
        case .weather: WeatherWidget(u: u)
        case .weatherHourly: WeatherHourlyWidget(u: u)
        case .music: MusicWidget(u: u)
        case .photos: PhotosWidget(u: u)
        case .battery: BatteryWidget(u: u)
        }
    }
}

// MARK: - 時鐘

struct AlarmDigitalWidget: View {
    let u: CGFloat
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let time = Fmt.clock(ctx.date)
            VStack(spacing: u * 2) {
                Text(time)
                    .font(.system(size: u * 52, weight: .semibold).width(.compressed))
                    .foregroundColor(Color(hex: 0x7BA7F2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: time)
                HStack(spacing: u * 2) {
                    Image(systemName: settings.alarmText == nil ? "alarm" : "alarm.fill")
                        .foregroundColor(settings.alarmText == nil ? .sbGray : .sbOrange)
                    Text(settings.alarmText ?? "沒有鬧鐘")
                        .foregroundColor(settings.alarmText == nil ? .sbGray : .white)
                }
                .font(.system(size: u * 8, weight: .semibold))
            }
            .padding(u * 4)
        }
    }
}

struct WorldClocksWidget: View {
    let u: CGFloat
    private let cities: [(String, String)] = [("台北", "Asia/Taipei"), ("東京", "Asia/Tokyo"),
                                              ("倫敦", "Europe/London"), ("紐約", "America/New_York")]

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: u * 4) {
                ForEach(cities, id: \.1) { name, id in
                    let tz = TimeZone(identifier: id) ?? .current
                    let hour = Calendar.current.dateComponents(in: tz, from: ctx.date).hour ?? 12
                    let isDay = (6..<18).contains(hour)
                    VStack(spacing: u * 1.5) {
                        AnalogDial(tint: isDay ? .black : .white,
                                   minorTint: (isDay ? Color.black : Color.white).opacity(0.3),
                                   handColor: isDay ? .black : .white,
                                   face: isDay ? .white : Color(hex: 0x2C2C2E),
                                   timeZone: tz, minuteTicks: false, smooth: false)
                            .frame(width: u * 31, height: u * 31)
                        Text(name).font(.system(size: u * 6, weight: .semibold)).foregroundColor(.white)
                        Text(offsetText(tz, ctx.date)).font(.system(size: u * 4.6)).foregroundColor(.sbGray)
                    }
                }
            }
            .padding(u * 4)
        }
    }

    private func offsetText(_ tz: TimeZone, _ now: Date) -> String {
        let diff = (tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        if diff == 0 { return "本地時間" }
        return diff > 0 ? "+\(diff) 小時" : "\(diff) 小時"
    }
}

// MARK: - 行事曆

struct CalendarDateWidget: View {
    let u: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.monthYear(ctx.date))
                    .font(.system(size: u * 11, weight: .medium))
                    .foregroundColor(.sbGray)
                HStack(alignment: .center, spacing: u * 3) {
                    Text(Fmt.day(ctx.date))
                        .font(.system(size: u * 62, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    weekday(ctx.date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(u * 5)
        }
    }

    @ViewBuilder private func weekday(_ d: Date) -> some View {
        if Fmt.isChinese {
            VStack(spacing: u * 0.5) {
                ForEach(Array(Fmt.weekdayLong(d)).map(String.init), id: \.self) { ch in
                    Text(ch)
                }
            }
            .font(.system(size: u * 13, weight: .semibold))
            .foregroundColor(.sbRed)
        } else {
            Text(Fmt.weekdayShort(d))
                .font(.system(size: u * 13, weight: .semibold))
                .foregroundColor(.sbRed)
        }
    }
}

enum MonthGrid {
    static func cells(for date: Date, cal: Calendar = .current) -> [Int?] {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: date)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let wd = cal.component(.weekday, from: start)
        let lead = (wd - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.map { Optional($0) }
    }

    static func weekdaySymbols(_ cal: Calendar = .current) -> [String] {
        let f = DateFormatter()
        f.locale = Fmt.locale
        let s = f.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let k = cal.firstWeekday - 1
        return Array(s[k...] + s[..<k])
    }

    static func isWeekend(column: Int, cal: Calendar = .current) -> Bool {
        let wd = (column + cal.firstWeekday - 1) % 7 + 1
        return wd == 1 || wd == 7
    }
}

struct CalendarMonthWidget: View {
    let u: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let cells = MonthGrid.cells(for: ctx.date)
            let today = Calendar.current.component(.day, from: ctx.date)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            VStack(alignment: .leading, spacing: u * 2.5) {
                Text(Fmt.monthName(ctx.date))
                    .font(.system(size: u * 7, weight: .bold))
                    .foregroundColor(.sbRed)
                    .padding(.leading, u * 2)
                LazyVGrid(columns: columns, spacing: u * 2.6) {
                    ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                        Text(s).font(.system(size: u * 5, weight: .semibold)).foregroundColor(.sbGray)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { i, day in
                        dayCell(day, column: i % 7, today: today)
                    }
                }
            }
            .padding(u * 4)
        }
    }

    @ViewBuilder private func dayCell(_ day: Int?, column: Int, today: Int) -> some View {
        if let day {
            let isToday = day == today
            Text("\(day)")
                .font(.system(size: u * 5.6, weight: isToday ? .bold : .semibold))
                .foregroundColor(isToday ? .white : (MonthGrid.isWeekend(column: column) ? .sbGray : .white))
                .frame(width: u * 9, height: u * 9)
                .background(Circle().fill(isToday ? Color.sbRed : .clear))
        } else {
            Color.clear.frame(width: u * 9, height: u * 9)
        }
    }
}

struct UpNextWidget: View {
    let u: CGFloat
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: u * 3.5) {
                HStack(alignment: .firstTextBaseline, spacing: u * 2) {
                    Text(Fmt.weekdayLong(ctx.date)).foregroundColor(.sbRed)
                    Text(Fmt.day(ctx.date)).foregroundColor(.white)
                }
                .font(.system(size: u * 9, weight: .semibold))

                if !calendar.authorized {
                    Button {
                        if calendar.denied { SystemLinks.openSettings() } else { calendar.requestIfNeeded() }
                    } label: {
                        Label("允許取用行事曆", systemImage: "calendar")
                            .font(.system(size: u * 6, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, u * 4).padding(.vertical, u * 2.5)
                            .background(Capsule().fill(Color.sbFill))
                    }
                    .buttonStyle(PressScaleStyle())
                } else if calendar.events.isEmpty {
                    Text("今天沒有其他行程")
                        .font(.system(size: u * 6.5, weight: .medium))
                        .foregroundColor(.sbGray)
                } else {
                    ForEach(Array(calendar.events.prefix(3)), id: \.self) { e in
                        eventRow(e)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(u * 5)
        }
        .onAppear { if settings.hasSeenWelcome { calendar.requestIfNeeded() } }
    }

    private func eventRow(_ e: EKEvent) -> some View {
        HStack(spacing: u * 2.5) {
            RoundedRectangle(cornerRadius: u * 0.6)
                .fill(Color(cgColor: e.calendar?.cgColor ?? UIColor.systemBlue.cgColor))
                .frame(width: u * 1.2, height: u * 13)
            VStack(alignment: .leading, spacing: u * 0.5) {
                Text(e.title ?? "行程")
                    .font(.system(size: u * 6.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(e.isAllDay ? "整天" : "\(Fmt.time(e.startDate)) – \(Fmt.time(e.endDate))")
                    .font(.system(size: u * 5.4))
                    .foregroundColor(.sbGray)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 天氣

struct WeatherWidget: View {
    let u: CGFloat
    @EnvironmentObject var weather: WeatherStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: u * 1.5) {
                Text(weather.place.isEmpty ? "我的位置" : weather.place)
                Image(systemName: "location.fill").font(.system(size: u * 5))
            }
            .font(.system(size: u * 7.5, weight: .semibold))
            .lineLimit(1)

            Text(Fmt.temp(weather.temperature, fahrenheit: settings.fahrenheit))
                .font(.system(size: u * 50, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .padding(.vertical, -u * 3)

            Spacer(minLength: 0)

            if weather.denied {
                Text("開啟定位服務以顯示天氣")
                    .font(.system(size: u * 6, weight: .medium))
                    .foregroundColor(.sbGray)
            } else {
                Image(systemName: weather.condition.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: u * 9))
                    .padding(.bottom, u * 1)
                Text(weather.condition.text)
                    .font(.system(size: u * 7.5, weight: .semibold))
                Text("最高 \(Fmt.temp(weather.high, fahrenheit: settings.fahrenheit)) 最低 \(Fmt.temp(weather.low, fahrenheit: settings.fahrenheit))")
                    .font(.system(size: u * 7.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(u * 5)
        .onAppear { if settings.hasSeenWelcome { weather.start() } }
        .accessibilityElement(children: .combine)
    }
}

struct WeatherHourlyWidget: View {
    let u: CGFloat
    @EnvironmentObject var weather: WeatherStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: u * 2) {
            HStack(spacing: u * 1.5) {
                Text(weather.place.isEmpty ? "我的位置" : weather.place)
                Image(systemName: "location.fill").font(.system(size: u * 4.5))
            }
            .font(.system(size: u * 7, weight: .semibold))
            Text(Fmt.temp(weather.temperature, fahrenheit: settings.fahrenheit))
                .font(.system(size: u * 26, weight: .medium))
            Text(weather.condition.text)
                .font(.system(size: u * 6.5, weight: .semibold))
                .foregroundColor(.sbGray)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(weather.hours.prefix(5)) { h in
                    VStack(spacing: u * 2) {
                        Text(Fmt.hourLabel(h.date))
                            .font(.system(size: u * 4.6, weight: .semibold))
                            .foregroundColor(.sbGray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: WeatherCode.info(h.code, isDay: h.isDay).symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: u * 7))
                            .frame(height: u * 8)
                        Text(Fmt.temp(h.temp, fahrenheit: settings.fahrenheit))
                            .font(.system(size: u * 6, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(u * 5)
        .onAppear { if settings.hasSeenWelcome { weather.start() } }
    }
}

// MARK: - 音樂

struct MusicWidget: View {
    let u: CGFloat
    @EnvironmentObject var music: MusicStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: u * 2) {
            HStack(alignment: .top) {
                Group {
                    if let art = music.artwork {
                        Image(uiImage: art).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.sbFill
                            Image(systemName: "music.note").font(.system(size: u * 16)).foregroundColor(.sbGray)
                        }
                    }
                }
                .frame(width: u * 38, height: u * 38)
                .clipShape(RoundedRectangle(cornerRadius: u * 3.5, style: .continuous))
                Spacer(minLength: 0)
                Button { music.openLibrary() } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: u * 7, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: u * 15, height: u * 15)
                        .background(Circle().fill(Color.sbFill))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("從資料庫選擇音樂")
            }

            Spacer(minLength: 0)
            Text(music.title ?? "未在播放")
                .font(.system(size: u * 7.5, weight: .bold))
                .lineLimit(1)
            Text(music.artist ?? (music.denied ? "需要取用「音樂」的權限" : "從資料庫挑選音樂"))
                .font(.system(size: u * 7))
                .foregroundColor(.sbGray)
                .lineLimit(1)

            Button { if music.hasItem { music.togglePlay() } else { music.openLibrary() } } label: {
                HStack(spacing: u * 2) {
                    Image(systemName: !music.hasItem ? "music.note.list" : (music.isPlaying ? "pause.fill" : "play.fill"))
                    Text(!music.hasItem ? "選擇音樂" : (music.isPlaying ? "暫停" : "播放"))
                }
                .font(.system(size: u * 7, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, u * 6)
                .frame(minHeight: u * 14)
                .background(Capsule().fill(Color.sbFill))
            }
            .buttonStyle(PressScaleStyle())
            .fixedSize()
            .padding(.top, u * 1)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(u * 5)
        .onAppear { if settings.hasSeenWelcome { music.start() } }
    }
}

// MARK: - 照片

struct PhotosWidget: View {
    let u: CGFloat
    @EnvironmentObject var photos: PhotoStore
    @EnvironmentObject var settings: SettingsStore
    @State private var image: UIImage?
    @State private var date: Date?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: u * 92, height: u * 92)
                    .clipShape(RoundedRectangle(cornerRadius: u * 10, style: .continuous))
                    .transition(.opacity)
                VStack(alignment: .leading, spacing: 0) {
                    Text("精選照片").font(.system(size: u * 6.5, weight: .bold))
                    if let date { Text(Fmt.fullDate(date)).font(.system(size: u * 5, weight: .semibold)) }
                }
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: u * 3)
                .padding(u * 9)
            } else if !photos.isAuthorized {
                PermissionPrompt(symbol: "photo.on.rectangle.angled", title: "精選照片",
                                 message: "允許取用照片以顯示回憶。", button: "允許取用", scale: u / 3.6) {
                    photos.request()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").font(.system(size: u * 20)).foregroundColor(.sbGray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photos.albums.count) { await load() }
        .onAppear { if settings.hasSeenWelcome { photos.start() } }
    }

    private func load() async {
        guard let album = photos.albums.first, album.assets.count > 0 else { return }
        let hourSeed = Int(Date().timeIntervalSince1970 / 3600)
        let asset = album.assets.object(at: hourSeed % album.assets.count)
        let img = await photos.image(for: asset, size: CGSize(width: u * 92 * 3, height: u * 92 * 3))
        withAnimation(.easeInOut(duration: 0.6)) {
            image = img
            date = asset.creationDate
        }
    }
}

// MARK: - 電池

struct BatteryWidget: View {
    let u: CGFloat
    @EnvironmentObject var battery: BatteryStore

    var body: some View {
        let color: Color = battery.level < 0.2 && !battery.isCharging ? .sbRed : .sbGreen
        VStack(spacing: u * 5) {
            ZStack {
                Circle().stroke(color.opacity(0.25), lineWidth: u * 6)
                Circle()
                    .trim(from: 0, to: battery.level)
                    .stroke(color, style: StrokeStyle(lineWidth: u * 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "ipad.landscape")
                    .font(.system(size: u * 16))
                    .foregroundColor(.white)
                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: u * 6))
                        .foregroundColor(color)
                        .offset(y: -u * 23.5)
                }
            }
            .frame(width: u * 56, height: u * 56)
            Text("\(Int((battery.level * 100).rounded()))%")
                .font(.system(size: u * 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .animation(.easeInOut(duration: 0.6), value: battery.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("電池 \(Int((battery.level * 100).rounded()))%")
    }
}
