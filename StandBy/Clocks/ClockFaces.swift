import SwiftUI
import MapKit

struct ClockFaceView: View {
    let style: ClockStyle
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let tint = settings.tint(for: style)
        switch style {
        case .analog: AnalogFullClock(tint: tint)
        case .digital: DigitalClockFace(tint: tint)
        case .world: WorldClockFace()
        case .solar: SolarClockFace()
        case .float: FloatClockFace(tint: tint)
        }
    }
}

// MARK: - 數字

struct DigitalClockFace: View {
    let tint: ClockTint
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var weather: WeatherStore

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            GeometryReader { geo in
                let W = geo.size.width, H = geo.size.height
                let time = Fmt.clock(ctx.date)
                HStack(spacing: 0) {
                    Text(time)
                        .font(.system(size: H * 1.02, weight: .semibold).width(.compressed))
                        .foregroundColor(tint.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.2)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: time)
                        .frame(width: W * 0.65, height: H * 1.3)
                        .padding(.leading, W * 0.04)
                        .padding(.trailing, W * 0.02)
                        .accessibilityLabel(Fmt.time(ctx.date))

                    VStack(alignment: .leading, spacing: H * 0.025) {
                        HStack(spacing: H * 0.015) {
                            Text(Fmt.weekdayShort(ctx.date)).foregroundColor(tint.day)
                            Text(Fmt.day(ctx.date)).foregroundColor(.white)
                        }
                        if weather.temperature != nil {
                            Text(Fmt.temp(weather.temperature, fahrenheit: settings.fahrenheit, unit: true))
                                .foregroundColor(.white)
                        }
                        Spacer(minLength: 0)
                        if let alarm = settings.alarmText {
                            Image(systemName: "alarm.fill").foregroundColor(tint.accent)
                            Text(alarm).foregroundColor(.white)
                        }
                    }
                    .font(.system(size: H * 0.082, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.vertical, H * 0.2)
                    .frame(maxWidth: .infinity, maxHeight: H, alignment: .leading)
                }
                .frame(width: W, height: H)
            }
        }
        .onAppear { if settings.hasSeenWelcome { weather.start() } }
    }
}

// MARK: - 浮動

struct FloatClockFace: View {
    let tint: ClockTint
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            GeometryReader { geo in
                let W = geo.size.width, H = geo.size.height
                let parts = Fmt.clockParts(ctx.date)
                let hour = Array(parts.hour), minute = Array(parts.minute)
                let n = CGFloat(hour.count + minute.count)
                let fs = min(H * 0.84, W / (n * 0.56 + 0.3))
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    HStack(spacing: -fs * 0.1) {
                        ForEach(Array(hour.enumerated()), id: \.offset) { i, ch in
                            digit(ch, slot: i, fs: fs, t: t)
                        }
                        colon(fs: fs, t: t).zIndex(10)
                        ForEach(Array(minute.enumerated()), id: \.offset) { i, ch in
                            digit(ch, slot: hour.count + i, fs: fs, t: t)
                        }
                    }
                    .compositingGroup()
                    .animation(.spring(response: 0.6, dampingFraction: 0.62), value: parts.hour + parts.minute)
                    .position(x: W / 2, y: H * 0.47)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Fmt.time(ctx.date))

                    if let alarm = settings.alarmText {
                        HStack(spacing: H * 0.012) {
                            Image(systemName: "alarm.fill").foregroundColor(.sbRed)
                            Text(alarm).foregroundColor(.white)
                        }
                        .font(.system(size: H * 0.065, weight: .semibold, design: .rounded))
                        .rotationEffect(.degrees(-6))
                        .position(x: W * 0.72, y: H * 0.9)
                    }
                }
            }
        }
    }

    private func digit(_ ch: Character, slot: Int, fs: CGFloat, t: Double) -> some View {
        Text(String(ch))
            .font(.system(size: fs, weight: .heavy, design: .rounded))
            .foregroundColor(slot % 2 == 0 ? tint.primary : tint.secondary)
            .fixedSize()
            .blendMode(.screen)
            .offset(y: sin(t * 0.55 + Double(slot) * 1.7) * fs * 0.022)
            .rotationEffect(.degrees(sin(t * 0.32 + Double(slot) * 2.1) * 2.2))
            .id("\(slot)-\(ch)")
            .transition(.asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity),
                                    removal: .scale(scale: 1.2).combined(with: .opacity)))
    }

    private func colon(fs: CGFloat, t: Double) -> some View {
        let d = fs * 0.2
        let ball = Circle()
            .fill(RadialGradient(colors: [Color(hex: 0xF4F7FC), Color(hex: 0xC9CDD4), Color(hex: 0xB4B8BF)],
                                 center: UnitPoint(x: 0.3, y: 0.35), startRadius: 0, endRadius: d * 0.7))
            .frame(width: d, height: d)
        return VStack(spacing: fs * 0.2) {
            ball.offset(x: sin(t * 0.7) * fs * 0.01)
            ball.offset(x: sin(t * 0.6 + 1) * fs * 0.012)
        }
        .frame(width: fs * 0.08)
        .offset(y: fs * 0.03)
    }
}

// MARK: - 太陽

struct SolarClockFace: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var weather: WeatherStore

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            GeometryReader { geo in
                let W = geo.size.width, H = geo.size.height
                let c = weather.effectiveCoordinate
                let sky = SkyPalette.sky(date: ctx.date, lat: c.latitude, lon: c.longitude)
                let time = Fmt.clock(ctx.date)
                ZStack {
                    LinearGradient(colors: [sky.bottom, sky.top], startPoint: .bottomLeading, endPoint: .topTrailing)
                    RadialGradient(colors: [sky.glow.opacity(0.75), sky.glow.opacity(0)], center: sky.glowPoint,
                                   startRadius: 0, endRadius: W * 0.62)
                        .blendMode(.screen)
                    Text(time)
                        .font(.system(size: H * 0.44, weight: .medium).width(.expanded))
                        .foregroundColor(.white.opacity(sky.textOpacity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .contentTransition(.numericText())
                        .padding(.horizontal, W * 0.06)
                        .accessibilityLabel(Fmt.time(ctx.date))
                }
                .frame(width: W, height: H)
                .animation(.easeInOut(duration: 2), value: time)
            }
        }
        .onAppear { if settings.hasSeenWelcome { weather.start() } }
    }
}

// MARK: - 世界

final class WorldMapSnapshot: ObservableObject {
    static let shared = WorldMapSnapshot()
    @Published var image: UIImage?
    private var loading = false

    /// MapKit 無法用單張快照涵蓋整個地球（會自動放大），所以切成 4×4 格分別拍攝，
    /// 再依每格實際投影的角落座標貼回 2048×2048 的麥卡托世界地圖。
    func load() {
        guard image == nil, !loading else { return }
        loading = true
        let world = MKMapRect.world
        let n = 4
        let tw = world.width / Double(n), th = world.height / Double(n)
        var tiles: [(MKMapRect, CGRect, MKMapSnapshotter.Snapshot)] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let cell: CGFloat = 2048 / CGFloat(n)
        for r in 0..<n {
            for c in 0..<n {
                let inner = MKMapRect(x: world.minX + Double(c) * tw, y: world.minY + Double(r) * th, width: tw, height: th)
                var padded = inner.insetBy(dx: -tw * 0.08, dy: -th * 0.08)
                padded = MKMapRect(x: padded.minX, y: max(world.minY, padded.minY), width: padded.width,
                                   height: min(world.maxY, padded.maxY) - max(world.minY, padded.minY))
                let o = MKMapSnapshotter.Options()
                o.mapRect = padded
                o.size = CGSize(width: 600, height: 600 * padded.height / padded.width)
                o.mapType = .satellite
                o.showsBuildings = false
                o.pointOfInterestFilter = .excludingAll
                let target = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                group.enter()
                MKMapSnapshotter(options: o).start(with: .global(qos: .userInitiated)) { snap, _ in
                    if let snap { lock.lock(); tiles.append((inner, target, snap)); lock.unlock() }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            self.loading = false
            guard tiles.count == n * n else { return }
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            self.image = UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 2048), format: fmt).image { ctx in
                for (inner, target, snap) in tiles {
                    let p1 = snap.point(for: MKMapPoint(x: inner.minX + 1, y: inner.minY + 1).coordinate)
                    let p2 = snap.point(for: MKMapPoint(x: inner.maxX - 1, y: inner.maxY - 1).coordinate)
                    let sx = (p2.x - p1.x) / target.width, sy = (p2.y - p1.y) / target.height
                    guard sx > 0.01, sy > 0.01 else { continue }
                    ctx.cgContext.saveGState()
                    ctx.cgContext.clip(to: target)
                    snap.image.draw(in: CGRect(x: target.minX - p1.x / sx, y: target.minY - p1.y / sy,
                                               width: snap.image.size.width / sx, height: snap.image.size.height / sy))
                    ctx.cgContext.restoreGState()
                }
            }
        }
    }
}

struct WorldClockFace: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var weather: WeatherStore
    @ObservedObject private var map = WorldMapSnapshot.shared
    @State private var pulse = false

    /// Web Mercator：經度 → x、緯度 → y（以地圖邊長為 1）。
    private static func project(lat: Double, lon: Double) -> CGPoint {
        let phi = max(-85, min(85, lat)) * .pi / 180
        return CGPoint(x: (lon + 180) / 360, y: 0.5 - log(tan(.pi / 4 + phi / 2)) / (2 * .pi))
    }

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            GeometryReader { geo in
                let W = geo.size.width, H = geo.size.height
                let side = W
                let top = Self.project(lat: 80, lon: 0).y
                let bottom = Self.project(lat: -62, lon: 0).y
                let originY = -top * side + (H - (bottom - top) * side) / 2
                let c = weather.effectiveCoordinate
                let me = Self.project(lat: c.latitude, lon: c.longitude)
                ZStack(alignment: .topLeading) {
                    Color.black
                    Group {
                        if let img = map.image {
                            Image(uiImage: img).resizable().interpolation(.high)
                                .saturation(0.75)
                                .brightness(-0.08)
                        } else {
                            Canvas { g, s in Self.drawGrid(&g, size: s) }
                        }
                    }
                    .frame(width: side, height: side)
                    .offset(y: originY)
                    .frame(width: W, height: H, alignment: .topLeading)
                    .clipped()

                    Canvas { g, s in Self.drawNight(&g, size: s, date: ctx.date) }
                        .frame(width: side, height: side)
                        .blur(radius: 18)
                        .offset(y: originY)
                        .frame(width: W, height: H, alignment: .topLeading)
                        .clipped()

                    ZStack {
                        Circle().stroke(Color.sbOrange.opacity(pulse ? 0 : 0.8), lineWidth: 3)
                            .frame(width: 22, height: 22)
                            .scaleEffect(pulse ? 3 : 1)
                        Circle().fill(Color.sbOrange).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    }
                    .position(x: me.x * side, y: me.y * side + originY)

                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill").font(.system(size: H * 0.035))
                            Text(weather.place.isEmpty ? TimeZone.current.localizedName(for: .shortGeneric, locale: Fmt.locale) ?? "本地" : weather.place)
                            Text("· \(Fmt.weekdayShort(ctx.date)) \(Fmt.day(ctx.date))").foregroundColor(.white.opacity(0.7))
                        }
                        .font(.system(size: H * 0.05, weight: .semibold))
                        Text(Fmt.clock(ctx.date))
                            .font(.system(size: H * 0.3, weight: .semibold).width(.condensed))
                            .contentTransition(.numericText())
                            .accessibilityLabel(Fmt.time(ctx.date))
                    }
                    .foregroundColor(.white)
                    .padding(.leading, W * 0.05)
                    .padding(.bottom, H * 0.04)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .frame(width: W, height: H)
                .clipped()
            }
        }
        .onAppear {
            map.load()
            if settings.hasSeenWelcome { weather.start() }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    /// 夜半球：依晨昏線把背向太陽的一側塗暗。
    private static func drawNight(_ g: inout GraphicsContext, size: CGSize, date: Date) {
        let sun = SolarMath.subsolar(date)
        let decl = sun.lat * .pi / 180
        let safeDecl = abs(decl) < 0.001 ? 0.001 : decl
        var path = Path()
        let steps = 180
        let poleY = project(lat: safeDecl > 0 ? -85 : 85, lon: 0).y * size.height
        path.move(to: CGPoint(x: 0, y: poleY))
        for s in 0...steps {
            let lon = -180 + Double(s) * 360 / Double(steps)
            let h = (lon - sun.lon) * .pi / 180
            let lat = atan(-cos(h) / tan(safeDecl)) * 180 / .pi
            let p = project(lat: lat, lon: lon)
            path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height))
        }
        path.addLine(to: CGPoint(x: size.width, y: poleY))
        path.closeSubpath()
        g.fill(path, with: .color(.black.opacity(0.62)))
    }

    private static func drawGrid(_ g: inout GraphicsContext, size: CGSize) {
        for lat in stride(from: -60.0, through: 75, by: 15) {
            for lon in stride(from: -180.0, through: 180, by: 6) {
                let p = project(lat: lat, lon: lon)
                g.fill(Path(ellipseIn: CGRect(x: p.x * size.width - 1.5, y: p.y * size.height - 1.5, width: 3, height: 3)),
                       with: .color(.white.opacity(0.18)))
            }
        }
    }
}
