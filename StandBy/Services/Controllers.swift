import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import UserNotifications

// MARK: - 電池

final class BatteryStore: ObservableObject {
    @Published var level: Double = 1
    @Published var state: UIDevice.BatteryState = .unknown

    var isCharging: Bool { Demo.enabled || state == .charging || state == .full }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        update()
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.update() }
        nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.update() }
    }

    private func update() {
        let l = UIDevice.current.batteryLevel
        level = l < 0 ? (Demo.enabled ? 0.72 : 1) : Double(l)
        state = UIDevice.current.batteryState
    }
}

// MARK: - 夜間模式與閒置熄螢幕

final class NightController: ObservableObject {
    @Published private(set) var isNight = false
    @Published private(set) var sleeping = false

    private var lastInteraction = Date()
    private var dimSaved: CGFloat?
    private var sleepSaved: CGFloat?

    func tick(_ now: Date, settings: SettingsStore) {
        let want: Bool
        switch settings.nightMode {
        case .on: want = true
        case .off: want = false
        case .auto:
            let c = Calendar.current.dateComponents([.hour, .minute], from: now)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let s = settings.nightStart, e = settings.nightEnd
            let inWindow = s > e ? (m >= s || m < e) : (m >= s && m < e)
            // iPad 沒有公開的環境光感測 API；開啟自動亮度時，螢幕亮度會隨環境光降低，用它來判斷「房間很暗」。
            let darkRoom = dimSaved == nil && sleepSaved == nil && UIScreen.main.brightness < 0.1
            want = inWindow || darkRoom
        }

        if want != isNight {
            withAnimation(.easeInOut(duration: 1.6)) { isNight = want }
        }
        applyDim(settings)

        if isNight, settings.nightSleep, !sleeping,
           now.timeIntervalSince(lastInteraction) > Double(settings.sleepAfter) {
            sleepSaved = UIScreen.main.brightness
            withAnimation(.easeInOut(duration: 2.5)) { sleeping = true }
            UIScreen.main.brightness = 0
        }
        if sleeping && (!isNight || !settings.nightSleep) { wake() }
    }

    func touch() {
        lastInteraction = Date()
        if sleeping { wake() }
    }

    private func wake() {
        if let b = sleepSaved { UIScreen.main.brightness = b; sleepSaved = nil }
        withAnimation(.easeOut(duration: 0.35)) { sleeping = false }
    }

    private func applyDim(_ settings: SettingsStore) {
        if isNight && settings.nightDimScreen {
            if dimSaved == nil {
                let current = sleepSaved ?? UIScreen.main.brightness
                dimSaved = current
                let target = max(0.04, min(current * 0.3, 0.15))
                if sleepSaved != nil { sleepSaved = target } else { UIScreen.main.brightness = target }
            }
        } else if let b = dimSaved {
            dimSaved = nil
            if sleepSaved != nil { sleepSaved = b } else { UIScreen.main.brightness = b }
        }
    }

    /// App 離開前景時把亮度還給使用者。
    func restoreBrightness() {
        if let b = sleepSaved { UIScreen.main.brightness = b; sleepSaved = nil }
        if let b = dimSaved { UIScreen.main.brightness = b; dimSaved = nil }
        sleeping = false
        lastInteraction = Date()
    }
}

// MARK: - 鬧鐘

final class AlarmController: ObservableObject {
    @Published private(set) var ringing = false

    private var lastFired: String?
    private var snoozeUntil: Date?
    private var soundTimer: Timer?

    func tick(_ now: Date, settings: SettingsStore) {
        if let s = snoozeUntil, now >= s, !ringing {
            snoozeUntil = nil
            fire()
            return
        }
        guard settings.alarmEnabled, !ringing else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(m)"
        if m == settings.alarmMinutes && lastFired != key {
            lastFired = key
            fire()
        }
    }

    func fire() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { ringing = true }
        soundTimer?.invalidate()
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        soundTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    func stop() {
        soundTimer?.invalidate()
        soundTimer = nil
        snoozeUntil = nil
        withAnimation(.easeInOut(duration: 0.35)) { ringing = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        VolumeController.shared.activateSession()
    }

    func snooze() {
        stop()
        snoozeUntil = Date().addingTimeInterval(9 * 60)
    }

    /// App 不在前景時，改用每日重複的本機通知提醒。
    func reschedule(_ settings: SettingsStore) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["standby.alarm"])
        guard settings.alarmEnabled else { return }
        let minutes = settings.alarmMinutes
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = "鬧鐘"
            content.body = Fmt.alarm(minutes: minutes)
            content.sound = .default
            var dc = DateComponents()
            dc.hour = minutes / 60
            dc.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: "standby.alarm", content: content, trigger: trigger))
        }
    }
}
