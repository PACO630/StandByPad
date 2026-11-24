import SwiftUI

/// 一個智慧型堆疊：上下滑動切換小工具，閒置時依情境自動輪替。
struct WidgetStackView: View {
    let stackID: Int
    let side: CGFloat
    let editing: Bool
    var interactive = true
    var onRemove: (WidgetItem) -> Void = { _ in }

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var music: MusicStore
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var battery: BatteryStore

    @State private var dotsVisible = false
    @State private var hideDots: DispatchWorkItem?
    @State private var lastInteraction = Date()

    private let rotateTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    static let suggestionID = UUID(uuidString: "00000000-0000-0000-0000-00000000AB01")!

    private var items: [WidgetItem] {
        var list = settings.stacks[safe: stackID] ?? []
        // 小工具建議：正在播放音樂、但兩個堆疊都沒有音樂小工具時，暫時把它加入右側堆疊。
        if settings.widgetSuggestions, !editing, stackID == 1, music.isPlaying,
           !settings.stacks.joined().contains(where: { $0.kind == .music }) {
            list.append(WidgetItem(id: Self.suggestionID, kind: .music))
        }
        return list
    }

    private func indexBinding(_ count: Int) -> Binding<Int> {
        Binding(
            get: { min(settings.stackIndex[safe: stackID] ?? 0, max(count - 1, 0)) },
            set: { v in
                guard settings.stackIndex.indices.contains(stackID) else { return }
                settings.stackIndex[stackID] = v
            })
    }

    var body: some View {
        let list = items
        let index = indexBinding(list.count)
        ZStack {
            if list.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.dashed").font(.system(size: side * 0.16))
                    Text("點一下「+」加入小工具").font(.system(size: side * 0.045, weight: .semibold))
                }
                .foregroundColor(.sbGray)
            } else {
                Pager(axis: .vertical, count: list.count, index: index, enabled: interactive, effect: .stack,
                      onDragging: { dragging in
                          lastInteraction = Date()
                          if dragging { showDots() } else { scheduleHide() }
                      }) { i in
                    card(list[i])
                }
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .trailing) {
            PageDots(count: list.count, index: index.wrappedValue, size: max(7, side * 0.014))
                .offset(x: side * 0.06 + 6)
                .opacity((dotsVisible || editing) && list.count > 1 ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: dotsVisible)
        }
        .onReceive(rotateTimer) { _ in rotateIfNeeded(list, index: index) }
        .onChange(of: index.wrappedValue) { _ in
            lastInteraction = Date()
            showDots()
            scheduleHide()
        }
        .onChange(of: music.isPlaying) { _ in
            lastInteraction = .distantPast
            rotateIfNeeded(items, index: indexBinding(items.count))
        }
    }

    private func card(_ item: WidgetItem) -> some View {
        WidgetView(kind: item.kind, side: side)
            .background(
                RoundedRectangle(cornerRadius: side * 0.12, style: .continuous)
                    .fill(Color.sbCard)
                    .opacity(editing ? 1 : 0))
            .overlay(alignment: .topLeading) {
                if editing && item.id != Self.suggestionID {
                    Button { onRemove(item) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: side * 0.05, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: side * 0.11, height: side * 0.11)
                            .background(Circle().fill(Color(hex: 0x636366)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .offset(x: -side * 0.035, y: -side * 0.035)
                    .accessibilityLabel("移除\(item.kind.title)")
                    .transition(.scale.combined(with: .opacity))
                }
            }
    }

    private func showDots() {
        hideDots?.cancel()
        dotsVisible = true
    }

    private func scheduleHide() {
        hideDots?.cancel()
        let work = DispatchWorkItem { dotsVisible = false }
        hideDots = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func rotateIfNeeded(_ list: [WidgetItem], index: Binding<Int>) {
        guard settings.smartRotate, !editing, list.count > 1,
              Date().timeIntervalSince(lastInteraction) > 90 else { return }
        let ctx = SmartRotation.Context(now: Date(), musicPlaying: music.isPlaying,
                                        nextEvent: calendar.nextEventDate,
                                        batteryLow: battery.level < 0.2 && !battery.isCharging)
        let scores = list.map { SmartRotation.score($0.kind, ctx) }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return }
        let current = index.wrappedValue
        guard best != current, scores[best] > (scores[safe: current] ?? 0) else { return }
        showDots()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { index.wrappedValue = best }
        scheduleHide()
    }
}

struct SideToggle: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(isOn ? Color.sbBlue : Color.white.opacity(0.2)))
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                    Text(isOn ? "開啟" : "關閉").font(.system(size: 15)).foregroundColor(.sbGray)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "開啟" : "關閉")
    }
}

/// 第一頁：左右兩個智慧型堆疊。長按任一堆疊進入編輯。
struct WidgetsPage: View {
    @Binding var editing: Bool
    let onSettings: () -> Void

    @EnvironmentObject var settings: SettingsStore
    @State private var editingStack: Int?
    @State private var showGallery = false
    @State private var removal: Removal?

    private struct Removal: Identifiable {
        let stack: Int
        let item: WidgetItem
        var id: UUID { item.id }
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let gap = W * 0.035
            let side = min((W - gap * 3) / 2, H * 0.9)
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    stackView(i, W: W, side: side, gap: gap)
                }
                if let s = editingStack {
                    editChrome(stack: s, W: W, side: side)
                        .transition(.opacity)
                }
                if showGallery {
                    WidgetGallery(onAdd: add, onClose: closeGallery)
                        .scrollModal()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(5)
                }
            }
            .frame(width: W, height: H)
        }
        .onAppear {
            if let s = DebugLaunch.state, s == "editWidgets" || s == "gallery" {
                editingStack = 1; editing = true; showGallery = s == "gallery"
            }
        }
        .alert("移除小工具？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
               presenting: removal) { r in
            Button("移除", role: .destructive) { remove(r) }
            Button("取消", role: .cancel) {}
        } message: { r in
            Text("「\(r.item.kind.title)」會從這個堆疊中移除。")
        }
    }

    private func stackView(_ i: Int, W: CGFloat, side: CGFloat, gap: CGFloat) -> some View {
        let restX = (i == 0 ? -1 : 1) * (side / 2 + gap / 2)
        let isEdited = editingStack == i
        let hidden = editingStack != nil && !isEdited
        return WidgetStackView(stackID: i, side: side, editing: isEdited, interactive: !hidden && !showGallery,
                               onRemove: { item in removal = Removal(stack: i, item: item) })
            .scaleEffect(isEdited ? 0.78 : (hidden ? 0.9 : 1))
            .offset(x: isEdited ? -W * 0.08 : restX)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .zIndex(isEdited ? 1 : 0)
            .onLongPressGesture(minimumDuration: 0.5) {
                guard editingStack == nil else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    editingStack = i
                    editing = true
                }
            }
    }

    private func editChrome(stack: Int, W: CGFloat, side: CGFloat) -> some View {
        ZStack {
            EditTopBar(onSettings: onSettings, onDone: exitEdit) {
                CapsuleButton(systemImage: "plus", label: "加入小工具") {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showGallery = true }
                }
            }
            VStack(spacing: 44) {
                SideToggle(symbol: "cellularbars", title: "智慧型輪替", isOn: $settings.smartRotate)
                SideToggle(symbol: "plus.rectangle.on.rectangle", title: "小工具建議", isOn: $settings.widgetSuggestions)
            }
            .offset(x: -W * 0.08 + side * 0.39 + W * 0.13)
        }
    }

    private func exitEdit() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            editingStack = nil
            showGallery = false
            editing = false
        }
    }

    private func closeGallery() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showGallery = false }
    }

    private func add(_ kind: WidgetKind) {
        guard let s = editingStack, settings.stacks.indices.contains(s) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            settings.stacks[s].append(WidgetItem(kind: kind))
            settings.stackIndex[s] = settings.stacks[s].count - 1
            showGallery = false
        }
    }

    private func remove(_ r: Removal) {
        guard settings.stacks.indices.contains(r.stack) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            settings.stacks[r.stack].removeAll { $0.id == r.item.id }
            let count = settings.stacks[r.stack].count
            settings.stackIndex[r.stack] = min(settings.stackIndex[r.stack], max(count - 1, 0))
        }
    }
}
