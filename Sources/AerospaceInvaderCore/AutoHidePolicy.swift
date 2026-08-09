import Foundation

/// Deep module that owns the auto-hide timer — one queue, one policy, no AppKit.
/// Previously `WorkspaceWindow` owned `hideTimer: Timer?` directly: scheduling in `show`
/// with `1.5s`, invalidation in `expand`, and `fadeOut` on fire. The interval was
/// hardcoded and untestable (needs a real run loop). Now the policy owns the timer and
/// the interval is injected so tests can assert scheduling without waiting.
///
/// The panel still decides *what* hides (it calls `fadeOut`), the policy decides *when*.
public final class AutoHidePolicy {
    private var timer: Timer?
    /// Auto-hide interval. Default 1.5s, matching the former window.
    public var interval: TimeInterval

    public init(interval: TimeInterval = 1.5) {
        self.interval = interval
    }

    /// Schedule auto-hide to fire after `interval`. Cancels any previous timer.
    public func schedule(onHide: @escaping () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            onHide()
        }
    }

    /// Cancel any pending auto-hide (e.g. when expanding).
    public func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        cancel()
    }
}
