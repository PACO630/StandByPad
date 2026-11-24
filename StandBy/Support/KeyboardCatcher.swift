import SwiftUI
import UIKit

/// 實體鍵盤：
/// - 單獨按一下 Option：叫出／關閉音樂介面
/// - ↑ ↓：調整音量（按住會連續調整）
/// - ← →：上一首／下一首
///
/// SwiftUI 在 iPadOS 16 沒辦法接收「只按修飾鍵」，所以用一個能成為第一回應者的 UIView 接收 UIPress。
struct KeyboardCatcher: UIViewRepresentable {
    var onOption: () -> Void
    var onVolume: (Int) -> Void
    var onTrack: (Int) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        apply(to: v)
        return v
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {
        apply(to: uiView)
        uiView.reclaimSoon()
    }

    private func apply(to v: CatcherView) {
        v.onOption = onOption
        v.onVolume = onVolume
        v.onTrack = onTrack
    }

    final class CatcherView: UIView {
        var onOption: (() -> Void)?
        var onVolume: ((Int) -> Void)?
        var onTrack: ((Int) -> Void)?

        private var optionDown = false
        private var optionCombined = false
        private var repeatTimer: Timer?
        private var textEditing = false
        private var observers: [NSObjectProtocol] = []

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            if observers.isEmpty {
                let nc = NotificationCenter.default
                observers.append(nc.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.textEditing = true
                })
                observers.append(nc.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.textEditing = false
                    self?.reclaimSoon()
                })
                observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.reclaimSoon()
                })
                // 其他畫面（例如設定表單）關閉後，重新取得鍵盤焦點。
                Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reclaim() }
            }
            reclaimSoon()
        }

        func reclaimSoon() {
            DispatchQueue.main.async { [weak self] in self?.reclaim() }
        }

        private func reclaim() {
            guard let w = window, !textEditing, !isFirstResponder,
                  w.rootViewController?.presentedViewController == nil else { return }
            becomeFirstResponder()
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key else { continue }
                switch key.keyCode {
                case .keyboardLeftAlt, .keyboardRightAlt:
                    optionDown = true
                    optionCombined = false
                    handled = true
                case .keyboardUpArrow, .keyboardDownArrow:
                    if optionDown { optionCombined = true }
                    let dir = key.keyCode == .keyboardUpArrow ? 1 : -1
                    onVolume?(dir)
                    startRepeat(dir)
                    handled = true
                case .keyboardLeftArrow, .keyboardRightArrow:
                    if optionDown { optionCombined = true }
                    onTrack?(key.keyCode == .keyboardRightArrow ? 1 : -1)
                    handled = true
                default:
                    if optionDown { optionCombined = true }
                }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key else { continue }
                switch key.keyCode {
                case .keyboardLeftAlt, .keyboardRightAlt:
                    if optionDown && !optionCombined && key.modifierFlags.subtracting(.alternate).isEmpty {
                        onOption?()
                    }
                    optionDown = false
                    handled = true
                case .keyboardUpArrow, .keyboardDownArrow:
                    stopRepeat()
                    handled = true
                case .keyboardLeftArrow, .keyboardRightArrow:
                    handled = true
                default:
                    break
                }
            }
            if !handled { super.pressesEnded(presses, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            optionDown = false
            stopRepeat()
            super.pressesCancelled(presses, with: event)
        }

        private func startRepeat(_ dir: Int) {
            stopRepeat()
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
                    self?.onVolume?(dir)
                }
            }
        }

        private func stopRepeat() {
            repeatTimer?.invalidate()
            repeatTimer = nil
        }
    }
}
