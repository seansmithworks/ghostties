import AppKit
import Foundation

/// A damped spring in Apple's terms: `response` is the period of the
/// undamped oscillation in seconds, `bounce` 0 is critically damped (no
/// overshoot) and higher values overshoot more (damping fraction
/// `1 - bounce`, as SwiftUI's `Spring(response:bounce:)`).
///
/// The sidebar ⇄ rail motion's one curve (`SidebarMotionDriver`). `advance`
/// is the closed-form solution from any position and velocity, so a step is
/// exact at any frame length and a retarget keeps its velocity.
struct SidebarSpring: Equatable {
    var response: Double
    var bounce: Double

    var dampingFraction: Double { 1 - min(max(bounce, 0), 0.9) }
    private var angularFrequency: Double { 2 * .pi / max(response, 0.01) }

    /// Displacement from the target and velocity after `dt` seconds,
    /// starting from displacement `x` and velocity `v`.
    func advance(x: Double, v: Double, dt: Double) -> (x: Double, v: Double) {
        let w0 = angularFrequency
        let zeta = dampingFraction
        if zeta >= 1 {
            // Critically damped.
            let a = x
            let b = v + w0 * x
            let decay = exp(-w0 * dt)
            return (decay * (a + b * dt), decay * (b - w0 * (a + b * dt)))
        }
        let decayRate = zeta * w0
        let wd = w0 * (1 - zeta * zeta).squareRoot()
        let a = x
        let b = (v + decayRate * x) / wd
        let decay = exp(-decayRate * dt)
        let c = cos(wd * dt)
        let s = sin(wd * dt)
        return (
            decay * (a * c + b * s),
            decay * ((-decayRate * a + b * wd) * c + (-decayRate * b - a * wd) * s)
        )
    }
}

/// Drives the sidebar ⇄ rail motion on one spring: one progress value, 0 at
/// the start of a segment and 1 at its end, and every constraint in the
/// segment written as a straight line between its start and its target at
/// that progress, every display frame. So the panel's width, the card's
/// gap and anything else that moves share one clock; SwiftUI reads the
/// width constraint (`SidebarMorphClock`), so the morph's leaves ride it too.
///
/// Why a solver and not `CASpringAnimation`: AppKit animates a constraint's
/// `constant` on its own timer, not as a layer animation, so a CA spring
/// can't be read frame by frame, can't be retargeted keeping its velocity,
/// and finishes on a computed duration rather than when it settles. Here a
/// retarget (`animate` while running) rebases every constraint on its
/// current value and carries the velocity over, and completions fire on
/// the frame the spring settles.
@MainActor
final class SidebarMotionDriver {
    private struct Channel {
        let constraint: NSLayoutConstraint
        var from: CGFloat
        var to: CGFloat
        var span: CGFloat { to - from }
    }

    private var channels: [Channel] = []
    /// The segment's progress: 0 at its start, 1 at its targets; passes 1
    /// on an overshoot.
    private(set) var progress: Double = 1
    /// d(progress)/dt.
    private(set) var velocity: Double = 0
    private(set) var spring = SidebarSpring(response: 0.35, bounce: 0)
    private var completions: [() -> Void] = []
    private var onFrame: ((Double) -> Void)?
    private var ticker: SidebarFrameTicker?
    private weak var view: NSView?

    /// Settled when every channel is within this many points of its target
    /// and moving slower than `settleSpeed` points per second.
    ///
    /// 0.5pt is a single pixel at 2x, and 20pt/s is a third of a point per
    /// frame at 60Hz: below both the motion reads as done, so the final snap
    /// is invisible, and the transition flag (which holds off the hover
    /// reveal, label clicks and the resize reclamp) clears when the motion
    /// looks finished rather than ~0.2s later in the sub-pixel tail.
    static let settleDistance: Double = 0.5
    static let settleSpeed: Double = 20

    /// `view` hosts the display link; nil drives nothing on its own (tests
    /// call `step`).
    init(view: NSView?) {
        self.view = view
    }

    // A window closed mid-spring: stop the display link and the timer. The
    // ticker also stops itself when its tick finds no driver.
    deinit {
        MainActor.assumeIsolated { ticker?.invalidate() }
    }

    #if DEBUG
    var tickerForTesting: SidebarFrameTicker? { ticker }
    #endif

    var isRunning: Bool { !channels.isEmpty }

    /// The current target of `constraint`, if it is moving.
    func target(of constraint: NSLayoutConstraint) -> CGFloat? {
        channels.first { $0.constraint === constraint }?.to
    }

    /// Springs every constraint in `targets` to its value. While already
    /// running this is a retarget: every constraint (including ones not in
    /// `targets`, which keep their targets) restarts from where it is, and
    /// the motion keeps its velocity. `completion` fires when the spring
    /// settles; earlier segments' completions fire then too, in order.
    func animate(
        _ targets: [(NSLayoutConstraint, CGFloat)],
        spring: SidebarSpring,
        onFrame: ((Double) -> Void)? = nil,
        completion: @escaping () -> Void
    ) {
        // Each running constraint's speed in points per second. Only these
        // carry velocity into the retarget: a constraint joining now (the
        // card's gap when Cmd+S pins a reveal) was at rest.
        var speeds: [ObjectIdentifier: Double] = [:]
        var merged: [(NSLayoutConstraint, CGFloat)] = []
        for channel in channels {
            speeds[ObjectIdentifier(channel.constraint)] = velocity * Double(channel.span)
            merged.append((channel.constraint, channel.to))
        }
        for (constraint, value) in targets {
            if let index = merged.firstIndex(where: { $0.0 === constraint }) {
                merged[index].1 = value
            } else {
                merged.append((constraint, value))
            }
        }
        channels = merged.map { Channel(constraint: $0.0, from: $0.0.constant, to: $0.1) }
        progress = 0
        // The velocity carried over, measured on the already-running
        // constraint with the furthest still to go.
        let running = channels.filter { speeds[ObjectIdentifier($0.constraint)] != nil && abs($0.span) > 0.01 }
        if let lead = running.max(by: { abs($0.span) < abs($1.span) }) {
            velocity = (speeds[ObjectIdentifier(lead.constraint)] ?? 0) / Double(lead.span)
        } else {
            velocity = 0
        }
        self.spring = spring
        self.onFrame = onFrame
        completions.append(completion)
        startTicking()
    }

    /// Advances the spring `dt` seconds and writes every constraint. Called
    /// by the display link; tests call it directly.
    func step(_ dt: Double) {
        guard isRunning else { return }
        let next = spring.advance(x: progress - 1, v: velocity, dt: max(dt, 0))
        progress = 1 + next.x
        velocity = next.v
        let reach = channels.map { abs(Double($0.span)) }.max() ?? 0
        if abs(next.x) * reach < Self.settleDistance && abs(next.v) * reach < Self.settleSpeed {
            progress = 1
            velocity = 0
        }
        for channel in channels {
            channel.constraint.constant = channel.from + channel.span * CGFloat(progress)
        }
        onFrame?(progress)
        if progress == 1 && velocity == 0 { finish() }
    }

    /// Stops where it is: no completions, constraints left at their
    /// current values. For another animation taking over the constraints.
    func cancel() {
        channels = []
        completions = []
        onFrame = nil
        progress = 1
        velocity = 0
        stopTicking()
    }

    private func finish() {
        channels = []
        onFrame = nil
        stopTicking()
        let pending = completions
        completions = []
        pending.forEach { $0() }
    }

    private func startTicking() {
        guard ticker == nil, let view else { return }
        ticker = SidebarFrameTicker(view: view) { [weak self] dt in
            guard let self else { return false }
            self.step(dt)
            return true
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }
}

/// Calls back once per display frame with the time since the last call:
/// the view's display link on macOS 14+. A display link stops for a window
/// that isn't on screen (occluded, another Space), and a spring that never
/// settles would leave the sidebar mid-transition, so a 60Hz timer backs it
/// up, stepping only when no frame has come for a while. Before macOS 14 the
/// timer alone, at 120Hz.
@MainActor
final class SidebarFrameTicker: NSObject {
    /// False once its driver is gone: the ticker then invalidates itself.
    private let tick: (Double) -> Bool
    private var displayLink: AnyObject?
    private var timer: Timer?
    private var last: CFTimeInterval?

    #if DEBUG
    var timerForTesting: Timer? { timer }
    #endif

    init(view: NSView, tick: @escaping (Double) -> Bool) {
        self.tick = tick
        super.init()
        var interval = 1.0 / 120
        if #available(macOS 14, *) {
            let link = view.displayLink(target: self, selector: #selector(frame(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            interval = 1.0 / 60
        }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.backstop() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @available(macOS 14, *)
    @objc private func frame(_ link: CADisplayLink) {
        advance(to: CACurrentMediaTime())
    }

    private func backstop() {
        let now = CACurrentMediaTime()
        // With a live display link, only when it has gone quiet.
        if displayLink != nil, let last, now - last < 1.0 / 40 { return }
        advance(to: now)
    }

    private func advance(to now: CFTimeInterval) {
        // The first frame advances one nominal frame, not zero.
        let dt = last.map { now - $0 } ?? (1.0 / 60)
        last = now
        if !tick(dt) { invalidate() }
    }

    func invalidate() {
        if #available(macOS 14, *) {
            (displayLink as? CADisplayLink)?.invalidate()
        }
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }
}
