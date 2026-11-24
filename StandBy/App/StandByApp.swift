import SwiftUI
import UIKit

@main
struct StandByApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings = SettingsStore()
    @StateObject private var night = NightController()
    @StateObject private var alarm = AlarmController()
    @StateObject private var weather = WeatherStore()
    @StateObject private var music = MusicStore()
    @StateObject private var calendar = CalendarStore()
    @StateObject private var photos = PhotoStore()
    @StateObject private var battery = BatteryStore()

    var body: some Scene {
        WindowGroup {
            StandByRootView()
                .environmentObject(settings)
                .environmentObject(night)
                .environmentObject(alarm)
                .environmentObject(weather)
                .environmentObject(music)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(battery)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .landscape
    }
}
