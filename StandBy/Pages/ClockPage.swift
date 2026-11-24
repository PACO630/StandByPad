import SwiftUI

/// 第三頁：全螢幕時鐘。上下滑動切換樣式；長按進入編輯，可選顏色。
struct ClockPage: View {
    @Binding var editing: Bool
    let onSettings: () -> Void

    @EnvironmentObject var settings: SettingsStore
    @State private var isEditing = false
    @State private var showPalette = false
    @State private var dotsVisible = false
    @State private var hideDots: DispatchWorkItem?

    private let styles = ClockStyle.allCases

    private var index: Binding<Int> {
        Binding(get: { styles.firstIndex(of: settings.clockStyle) ?? 0 },
                set: { i in
                    settings.clockStyle = styles[min(max(i, 0), styles.count - 1)]
                    showPalette = false
                })
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let radius: CGFloat = isEditing ? 48 : 0
            ZStack {
                Pager(axis: .vertical, count: styles.count, index: index, effect: .stack,
                      onDragging: { d in if d { showDots() } else { scheduleHide() } }) { i in
                    ClockFaceView(style: styles[i])
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(isEditing ? 0.22 : 0), lineWidth: 2.5))
                .scaleEffect(isEditing ? 0.78 : 1)
                .onLongPressGesture(minimumDuration: 0.5) { enterEdit() }

                PageDots(count: styles.count, index: index.wrappedValue)
                    .position(x: isEditing ? W / 2 + W * 0.39 + 30 : W - 26, y: H / 2)
                    .opacity(dotsVisible || isEditing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: dotsVisible)

                if isEditing {
                    EditTopBar(title: settings.clockStyle.title, onSettings: onSettings, onDone: exitEdit) { EmptyView() }
                        .transition(.opacity)
                    paletteControls(W: W, H: H)
                        .transition(.opacity)
                }
            }
            .frame(width: W, height: H)
        }
        .onChange(of: isEditing) { editing = $0 }
        .onChange(of: settings.clockStyle) { _ in
            showDots()
            scheduleHide()
        }
        .onAppear {
            if let s = DebugLaunch.state, s == "editClock" || s == "palette" {
                isEditing = true; showPalette = s == "palette"
            }
        }
    }

    @ViewBuilder private func paletteControls(W: CGFloat, H: CGFloat) -> some View {
        let palette = settings.clockStyle.palette
        if palette.count > 1 {
            let selected = settings.colorIndex(for: settings.clockStyle)
            ZStack {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPalette.toggle() }
                } label: {
                    Circle()
                        .fill(palette[selected].swatch)
                        .frame(width: 34, height: 34)
                        .padding(7)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 3))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("選擇顏色")
                .position(x: W / 2 + W * 0.39 - 44, y: H / 2 + H * 0.39 - 44)

                if showPalette {
                    HStack(spacing: 14) {
                        ForEach(palette.indices, id: \.self) { i in
                            Button {
                                withAnimation(.easeInOut(duration: 0.35)) { settings.setColor(i, for: settings.clockStyle) }
                            } label: {
                                Circle()
                                    .fill(palette[i].swatch)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.white, lineWidth: i == selected ? 3 : 0).padding(-5))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel("顏色 \(i + 1)")
                            .accessibilityAddTraits(i == selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: 0x2C2C2E)))
                    .position(x: W / 2, y: H - 46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func enterEdit() {
        guard !isEditing else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { isEditing = true }
    }

    private func exitEdit() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isEditing = false
            showPalette = false
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
}
