import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

enum PagerEffect { case slide, stack }

/// 待機模式使用的分頁器：水平切換三個畫面、垂直切換堆疊中的小工具／時鐘樣式。
/// 方向鎖定讓水平與垂直分頁器可以巢狀使用；兩端有橡皮筋回彈。
struct Pager<Content: View>: View {
    let axis: Axis
    let count: Int
    @Binding var index: Int
    let enabled: Bool
    let effect: PagerEffect
    let onDragging: (Bool) -> Void
    let content: (Int) -> Content

    private struct DragState: Equatable {
        var lock: Bool? = nil
        var offset: CGFloat = 0
    }

    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.42, dampingFraction: 0.86)))
    private var drag = DragState()

    /// 觸控板雙指滑動／滑鼠滾輪（經由 ScrollRouter）。
    @StateObject private var scroll: ScrollTarget

    init(axis: Axis, count: Int, index: Binding<Int>, enabled: Bool = true, effect: PagerEffect = .slide,
         onDragging: @escaping (Bool) -> Void = { _ in },
         @ViewBuilder content: @escaping (Int) -> Content) {
        self.axis = axis
        self.count = count
        self._index = index
        self.enabled = enabled
        self.effect = effect
        self.onDragging = onDragging
        self.content = content
        _scroll = StateObject(wrappedValue: ScrollTarget(axis: axis))
    }

    private var current: Int { min(max(index, 0), max(count - 1, 0)) }

    private var visible: [Int] {
        guard count > 0 else { return [] }
        return Array(max(0, current - 1)...min(count - 1, current + 1))
    }

    /// 手指拖曳與觸控板捲動的位移合併；兩端套用橡皮筋效果。
    private func totalOffset(_ length: CGFloat) -> CGFloat {
        var s = scroll.offset
        if (current == 0 && s > 0) || (current == count - 1 && s < 0) { s = rubberBand(s, length) }
        return drag.offset + s
    }

    var body: some View {
        let _ = (scroll.enabled = enabled && count > 0)
        GeometryReader { geo in
            let length = axis == .horizontal ? geo.size.width : geo.size.height
            ZStack {
                ForEach(visible, id: \.self) { i in
                    page(i, size: geo.size, length: length)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(length: length))
            .onAppear {
                scroll.frame = geo.frame(in: .global)
                ScrollRouter.shared.register(scroll)
            }
            .onChange(of: geo.frame(in: .global)) { scroll.frame = $0 }
            .onChange(of: scroll.endTick) { _ in finishScroll(length: length) }
        }
        .onDisappear { ScrollRouter.shared.unregister(scroll) }
        .onChange(of: drag.lock == true || scroll.offset != 0) { dragging in onDragging(dragging) }
    }

    private func finishScroll(length: CGFloat) {
        let e = scroll.lastEnd
        var target = current
        if enabled, count > 0 {
            // 觸控板慣性大、滾輪一格位移小：用較低的距離門檻或速度判斷翻頁。
            let threshold = min(length * 0.2, 60)
            if e.translation < -threshold || e.velocity < -400 { target += 1 }
            else if e.translation > threshold || e.velocity > 400 { target -= 1 }
            target = min(max(target, 0), count - 1)
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            index = target
            scroll.offset = 0
        }
    }

    private func page(_ i: Int, size: CGSize, length: CGFloat) -> some View {
        let pos = CGFloat(i - current) * length + totalOffset(length)
        let p = min(abs(pos) / max(length, 1), 1)
        return content(i)
            .frame(width: size.width, height: size.height)
            .scaleEffect(effect == .stack ? 1 - p * 0.14 : 1)
            .opacity(effect == .stack ? Double(1 - p) : 1)
            .offset(x: axis == .horizontal ? pos : 0, y: axis == .vertical ? pos : 0)
            .allowsHitTesting(i == current)
            .zIndex(i == current ? 1 : 0)
            .accessibilityHidden(i != current)
    }

    private func dragGesture(length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                guard enabled, count > 0 else { return }
                if state.lock == nil {
                    let dx = abs(value.translation.width), dy = abs(value.translation.height)
                    state.lock = axis == .horizontal ? dx > dy : dy > dx
                }
                guard state.lock == true else { return }
                var t = axis == .horizontal ? value.translation.width : value.translation.height
                if (current == 0 && t > 0) || (current == count - 1 && t < 0) {
                    t = rubberBand(t, length)
                }
                state.offset = t
            }
            .onEnded { value in
                guard enabled, count > 0 else { return }
                let dx = abs(value.translation.width), dy = abs(value.translation.height)
                guard axis == .horizontal ? dx > dy : dy > dx else { return }
                let t = axis == .horizontal ? value.translation.width : value.translation.height
                let predicted = axis == .horizontal ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                var target = current
                if t < -length * 0.3 || predicted < -length * 0.5 { target += 1 }
                else if t > length * 0.3 || predicted > length * 0.5 { target -= 1 }
                target = min(max(target, 0), count - 1)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { index = target }
            }
    }

    private func rubberBand(_ x: CGFloat, _ d: CGFloat) -> CGFloat {
        let c: CGFloat = 0.55
        let s: CGFloat = x < 0 ? -1 : 1
        return s * (1 - 1 / (abs(x) * c / max(d, 1) + 1)) * d
    }
}

struct PageDots: View {
    let count: Int
    let index: Int
    var axis: Axis = .vertical
    var size: CGFloat = 8

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: size * 0.9))
            : AnyLayout(HStackLayout(spacing: size * 0.9))
        layout {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == index ? 0.95 : 0.3))
                    .frame(width: size, height: size)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index)
        .accessibilityElement()
        .accessibilityLabel("第 \(index + 1) 頁，共 \(count) 頁")
    }
}

// MARK: - 偵測任何觸碰（喚醒夜間熄螢幕用），不攔截觸控事件。

struct TouchObserver: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.onTouch = onTouch
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) { uiView.onTouch = onTouch }

    final class HostView: UIView {
        var onTouch: (() -> Void)?
        private weak var installedOn: UIWindow?
        private lazy var recognizer: TouchDownRecognizer = {
            let r = TouchDownRecognizer(target: nil, action: nil)
            r.cancelsTouchesInView = false
            r.delaysTouchesBegan = false
            r.delaysTouchesEnded = false
            r.handler = { [weak self] in self?.onTouch?() }
            r.delegate = r
            return r
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let w = window, installedOn !== w else { return }
            w.addGestureRecognizer(recognizer)
            installedOn = w
        }
    }
}

final class TouchDownRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var handler: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        handler?()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
