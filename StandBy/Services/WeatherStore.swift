import Foundation
import CoreLocation
import SwiftUI

enum WeatherCode {
    /// WMO 天氣代碼 → SF Symbol 與中文描述。
    static func info(_ code: Int, isDay: Bool) -> (symbol: String, text: String) {
        switch code {
        case 0: return (isDay ? "sun.max.fill" : "moon.stars.fill", "晴朗")
        case 1: return (isDay ? "sun.max.fill" : "moon.fill", "大致晴朗")
        case 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "局部多雲")
        case 3: return ("cloud.fill", "多雲")
        case 45, 48: return ("cloud.fog.fill", "霧")
        case 51, 53, 55: return ("cloud.drizzle.fill", "毛毛雨")
        case 56, 57: return ("cloud.sleet.fill", "凍毛毛雨")
        case 61: return ("cloud.rain.fill", "小雨")
        case 63: return ("cloud.rain.fill", "雨")
        case 65: return ("cloud.heavyrain.fill", "大雨")
        case 66, 67: return ("cloud.sleet.fill", "凍雨")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "雪")
        case 80, 81: return (isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill", "陣雨")
        case 82: return ("cloud.heavyrain.fill", "強陣雨")
        case 85, 86: return ("cloud.snow.fill", "陣雪")
        case 95: return ("cloud.bolt.rain.fill", "雷雨")
        case 96, 99: return ("cloud.bolt.rain.fill", "雷雨伴有冰雹")
        default: return ("cloud.fill", "—")
        }
    }
}

/// 天氣資料來自 Open-Meteo（免金鑰）；位置透過 CoreLocation，地區名稱用反向地理編碼。
final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Hour: Identifiable {
        let id: Int
        let date: Date
        let temp: Double
        let code: Int
        let isDay: Bool
    }

    @Published var place: String = ""
    @Published var temperature: Double?
    @Published var high: Double?
    @Published var low: Double?
    @Published var code: Int = 0
    @Published var isDay = true
    @Published var hours: [Hour] = []
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var denied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var started = false
    private var timer: Timer?
    private var lastLocation: CLLocation?

    var condition: (symbol: String, text: String) { WeatherCode.info(code, isDay: isDay) }

    /// 沒有位置時，太陽與世界時鐘用台北的座標估算。
    var effectiveCoordinate: CLLocationCoordinate2D {
        coordinate ?? CLLocationCoordinate2D(latitude: 25.033, longitude: 121.565)
    }

    func start() {
        guard !started else { return }
        started = true
        if Demo.enabled {
            place = "太平區"; temperature = 27; high = 30; low = 24; code = 3; isDay = true
            coordinate = CLLocationCoordinate2D(latitude: 24.13, longitude: 120.72)
            let now = Date()
            hours = (0..<6).map { i in
                Hour(id: i, date: now.addingTimeInterval(Double(i) * 3600), temp: 27 - Double(i) * 0.6,
                     code: [3, 2, 2, 61, 3, 1][i], isDay: true)
            }
            return
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        handleAuthorization()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard started, !Demo.enabled else { return }
        handleAuthorization()
        if let l = lastLocation { Task { await self.fetch(l.coordinate) } }
    }

    private func handleAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            denied = false
            manager.requestLocation()
        default:
            denied = true
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.handleAuthorization() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = loc
            self.coordinate = loc.coordinate
            self.geocoder.reverseGeocodeLocation(loc, preferredLocale: Fmt.locale) { marks, _ in
                guard let p = marks?.first else { return }
                DispatchQueue.main.async { self.place = p.subLocality ?? p.locality ?? p.name ?? "" }
            }
            Task { await self.fetch(loc.coordinate) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func fetch(_ c: CLLocationCoordinate2D) async {
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)"
            + "&current=temperature_2m,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code,is_day"
            + "&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&timeformat=unixtime&forecast_days=2"
        guard let url = URL(string: s) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(OpenMeteo.self, from: data)
            let now = Date()
            var hrs: [Hour] = []
            for (i, t) in r.hourly.time.enumerated() where hrs.count < 6 {
                let d = Date(timeIntervalSince1970: t)
                guard d > now.addingTimeInterval(-1800), i < r.hourly.temperature_2m.count else { continue }
                hrs.append(Hour(id: Int(t), date: d, temp: r.hourly.temperature_2m[i],
                                code: r.hourly.weather_code[i], isDay: r.hourly.is_day[i] == 1))
            }
            let nextHours = hrs
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.temperature = r.current.temperature_2m
                    self.code = r.current.weather_code
                    self.isDay = r.current.is_day == 1
                    self.high = r.daily.temperature_2m_max.first
                    self.low = r.daily.temperature_2m_min.first
                    self.hours = nextHours
                }
            }
        } catch {
            // 網路暫時不可用：保留上一次的資料，30 分鐘後再試。
        }
    }
}

private struct OpenMeteo: Decodable {
    struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
    struct Hourly: Decodable { let time: [TimeInterval]; let temperature_2m: [Double]; let weather_code: [Int]; let is_day: [Int] }
    struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
    let current: Current
    let hourly: Hourly
    let daily: Daily
}
