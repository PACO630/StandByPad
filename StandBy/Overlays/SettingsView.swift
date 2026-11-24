import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var weather: WeatherStore
    @EnvironmentObject var photos: PhotoStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    private func timeBinding(_ value: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                value.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("夜間模式", selection: $settings.nightMode) {
                        ForEach(NightModeSetting.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.nightMode == .auto {
                        DatePicker("開始時間", selection: timeBinding($settings.nightStart), displayedComponents: .hourAndMinute)
                        DatePicker("結束時間", selection: timeBinding($settings.nightEnd), displayedComponents: .hourAndMinute)
                    }
                    Toggle("夜間降低螢幕亮度", isOn: $settings.nightDimScreen)
                    Toggle("夜間閒置時讓畫面變黑", isOn: $settings.nightSleep)
                    if settings.nightSleep {
                        Picker("閒置多久後", selection: $settings.sleepAfter) {
                            Text("30 秒").tag(30)
                            Text("1 分鐘").tag(60)
                            Text("2 分鐘").tag(120)
                            Text("5 分鐘").tag(300)
                            Text("10 分鐘").tag(600)
                        }
                    }
                } header: {
                    Text("夜間模式")
                }

                Section {
                    Toggle("鬧鐘", isOn: $settings.alarmEnabled)
                    if settings.alarmEnabled {
                        DatePicker("時間", selection: timeBinding($settings.alarmMinutes), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("鬧鐘")
                }

                Section("小工具") {
                    Toggle("智慧型輪替", isOn: $settings.smartRotate)
                    Toggle("小工具建議", isOn: $settings.widgetSuggestions)
                    Button("重設兩個小工具堆疊", role: .destructive) { confirmReset = true }
                }

                Section("天氣") {
                    Picker("溫度單位", selection: $settings.fahrenheit) {
                        Text("攝氏 °C").tag(false)
                        Text("華氏 °F").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Button("重新整理天氣") { weather.refresh() }
                }

                if !photos.albums.isEmpty {
                    Section {
                        ForEach(photos.albums) { album in
                            Toggle(album.title, isOn: Binding(
                                get: { !settings.hiddenAlbums.contains(album.id) },
                                set: { show in
                                    if show { settings.hiddenAlbums.removeAll { $0 == album.id } }
                                    else if !settings.hiddenAlbums.contains(album.id) { settings.hiddenAlbums.append(album.id) }
                                }))
                        }
                    } header: {
                        Text("照片中顯示的相簿")
                    }
                }

                Section {
                    Text("@paco._0630")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("待機模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("重設小工具堆疊？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重設", role: .destructive) { settings.resetStacks() }
                Button("取消", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }
}
