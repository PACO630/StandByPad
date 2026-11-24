import SwiftUI
import UIKit

/// 一個可接收觸控板／滑鼠滾輪捲動的區域（分頁器、全螢幕播放器、彈出面板）。
final class ScrollTarget: ObservableObject {
    /// nil 代表兩個方向都接受。
    var axis: Axis?
    var enabled = true
    /// 全域座標中的範圍；.infinite 代表整個視窗。
    var frame: CGRect = .zero
    /// 只要有任何 modal 目標存在，就只有 modal 目標能接收捲動（避免捲動穿透到後面的畫面）。
    var modal = false

    @Published var offset: CGFloat = 0
    @Published private(set) var endTick = 0
    private(set) var lastEnd: (translation: CGFloat, velocity: CGFloat, axis: Axis) = (0, 0, .horizontal)

    init(axis: Axis?, modal: Bool = false) {
        self.axis = axis
        self.modal = modal
    }

    fileprivate func finish(_ t: CGFloat, _ v: CGFloat, _ axis: Axis) {
        lastEnd = (t, v, axis)
        endTick += 1
    }
}

/// iPadOS 的觸控板雙指滑動與滑鼠滾輪是「捲動事件」，SwiftUI 的 DragGesture 收不到。
/// 這裡在視窗上掛一個只接收捲動的 UIPanGestureRecognizer，依指標位置與方向分派給最內層的目標。
final class ScrollRouter: NSObject, UIGestureRecognizerDelegate {
    static let shared = ScrollRouter()

    private let targets = NSHashTable<ScrollTarget>.weakObjects()
    private weak var active: ScrollTarget?
    private var activeAxis: Axis = .horizontal
    private weak var installedWindow: UIWindow?

    func register(_ t: ScrollTarget) { targets.add(t) }
    func unregister(_ t: ScrollTarget) {
        targets.remove(t)
        if active === t { active = nil }
    }

    func install(on window: UIWindow) {
        guard installedWindow !== window else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        pan.allowedScrollTypesMask = .all
        pan.allowedTouchTypes = []          // 手指與指標點按拖曳仍交給 SwiftUI 手勢
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delegate = self
        window.addGestureRecognizer(pan)
        installedWindow = window
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func handle(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view else { return }
        let t = pan.translation(in: view), v = pan.velocity(in: view)
        switch pan.state {
        case .began:
            let loc = pan.location(in: view)
            let axis: Axis = abs(t.x) + abs(v.x) * 0.05 >= abs(t.y) + abs(v.y) * 0.05 ? .horizontal : .vertical
            let all = targets.allObjects
            let anyModal = all.contains { $0.modal }
            let candidates = all.filter { target in
                (!anyModal || target.modal) && target.enabled && target.frame.contains(loc)
                    && (target.axis == nil || target.axis == axis)
            }
            active = candidates.min { area($0.frame) < area($1.frame) }
            activeAxis = axis
            update(t)
        case .changed:
            update(t)
        case .ended, .cancelled, .failed:
            guard let target = active else { return }
            let along = activeAxis == .horizontal ? t.x : t.y
            let vel = activeAxis == .horizontal ? v.x : v.y
            target.finish(along, pan.state == .ended ? vel : 0, activeAxis)
            active = nil
        default:
            break
        }
    }

    private func update(_ t: CGPoint) {
        guard let target = active else { return }
        target.offset = activeAxis == .horizontal ? t.x : t.y
    }

    private func area(_ r: CGRect) -> CGFloat { r.isInfinite ? .greatestFiniteMagnitude : r.width * r.height }
}

/// 掛在根畫面背景，把 ScrollRouter 安裝到視窗上。
struct ScrollRouterInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ uiView: HostView, context: Context) {}

    final class HostView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let w = window { ScrollRouter.shared.install(on: w) }
        }
    }
}

extension View {
    /// 讓這個畫面在出現期間攔下所有觸控板／滾輪捲動（可選擇處理捲動結束）。
    func scrollModal(axis: Axis? = nil, onEnd: ((_ translation: CGFloat, _ velocity: CGFloat, _ axis: Axis) -> Void)? = nil) -> some View {
        modifier(ScrollModalModifier(axis: axis, onEnd: onEnd))
    }
}

private struct ScrollModalModifier: ViewModifier {
    let axis: Axis?
    let onEnd: ((CGFloat, CGFloat, Axis) -> Void)?
    @StateObject private var target: ScrollTarget

    init(axis: Axis?, onEnd: ((CGFloat, CGFloat, Axis) -> Void)?) {
        self.axis = axis
        self.onEnd = onEnd
        _target = StateObject(wrappedValue: ScrollTarget(axis: axis, modal: true))
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                target.frame = .infinite
                ScrollRouter.shared.register(target)
            }
            .onDisappear { ScrollRouter.shared.unregister(target) }
            .onChange(of: target.endTick) { _ in
                let e = target.lastEnd
                target.offset = 0
                onEnd?(e.translation, e.velocity, e.axis)
            }
    }
}
