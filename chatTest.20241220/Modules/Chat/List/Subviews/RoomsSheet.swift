import SwiftUI
import UIKit
import Combine

import UIKit

/// A UIScrollView subclass specifically designed to host UIHostingController.
/// It overrides key targeting methods to completely shut down automatic offset/focus shifting.
import UIKit

class NonAutoScrollingScrollView: UIScrollView {
    /// Tracks if we are actively panning the container sheet (allows gestures to drive offsets)
    var isPanningSheet: Bool = false

    /// True only when the panel is expanded — i.e. the content is allowed to scroll freely.
    /// While collapsed this is false, and the scroll view stays hard-pinned to the top.
    var allowsContentScroll: Bool = false

    /// Whether an offset change is legitimately user- or gesture-driven (vs. a silent
    /// layout-engine update we want to suppress while collapsed).
    private var isUserDriven: Bool {
        isDragging || isDecelerating || isTracking || isZooming || isPanningSheet
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        // Honor offset changes when scrolling is allowed (expanded) or when they're driven by
        // natural touch interactions / the custom sheet gesture. Otherwise ignore the
        // UIHostingController's automatic internal offset resets that cut off the top rows.
        if allowsContentScroll || isUserDriven {
            super.setContentOffset(contentOffset, animated: animated)
        }
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        // Prevent automatic focus scroll attempts from the underlying UIHostingController
        // unless scrolling is allowed or the user is actively interacting.
        if allowsContentScroll || isUserDriven {
            super.scrollRectToVisible(rect, animated: animated)
        } 
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Runs AFTER UIKit's internal, layout-driven offset adjustments — which reach the
        // `contentOffset` property directly and so bypass the setter override above. While
        // collapsed and not user-interacting, hard-pin the top so async content growth
        // (rooms loading) can't leave the list resting scrolled-down on first presentation.
        if !allowsContentScroll && !isUserDriven && contentOffset.y != 0 {
            contentOffset.y = 0
        }
    }
}


/// A resizable bottom panel (Apple-Maps style) holding the rooms list.
///
/// On iOS this is a UIKit panel driven by a **single** pan gesture that coordinates resize and
/// inner scrolling (the SwiftUI `DragGesture` ↔ `ScrollView` split caused a two-phase "shake").
/// One gesture moves the panel while pinning the scroll offset, then hands off to scrolling at the
/// expanded detent, and collapses on pull-down at the top. The area above the panel passes touches
/// through (UIKit `hitTest`) so the SwiftUI header behind stays tappable.
struct RoomsSheet<Content: View>: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    /// Top inset (from the safe-area top) when collapsed — how much header shows above.
    let collapsedTopInset: CGFloat
    /// Reports the panel's expand progress (0 = collapsed, 1 = fully expanded) every frame, both while
    /// dragging and during the spring settle. Lets the header behind fade/slide in lockstep.
    var onProgress: ((CGFloat) -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        #if os(iOS)
        RoomsSheetRepresentable(
            collapsedTopInset: collapsedTopInset,
            panelBackground: UIColor(selectedTheme.colors(for: colorScheme).background),
            grabberColor: UIColor(selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.4)),
            hairlineColor: UIColor(selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.12)),
            onProgress: onProgress,
            content: content
        )
        .ignoresSafeArea(edges: .bottom)
        #else
        ScrollView { content }
            .scrollIndicators(.hidden)
        #endif
    }
}

#if os(iOS)

private struct RoomsSheetRepresentable<Content: View>: UIViewControllerRepresentable {
    let collapsedTopInset: CGFloat
    let panelBackground: UIColor
    let grabberColor: UIColor
    let hairlineColor: UIColor
    let onProgress: ((CGFloat) -> Void)?
    let content: Content

    func makeUIViewController(context: Context) -> RoomsSheetController<Content> {
        let vc = RoomsSheetController(
            collapsedTopInset: collapsedTopInset,
            panelBackground: panelBackground,
            grabberColor: grabberColor,
            hairlineColor: hairlineColor,
            content: content
        )
        vc.onProgress = onProgress
        return vc
    }

    func updateUIViewController(_ vc: RoomsSheetController<Content>, context: Context) {
        vc.onProgress = onProgress
        vc.update(
            collapsedTopInset: collapsedTopInset,
            panelBackground: panelBackground,
            grabberColor: grabberColor,
            hairlineColor: hairlineColor,
            content: content
        )
    }
}

/// Root view that only swallows touches landing on the panel; everything above the panel passes
/// through to the SwiftUI header/gradient behind it.
private final class PassthroughView: UIView {
    weak var panel: UIView?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let panel else { return nil }
        // Only intercept touches inside the panel's current frame.
        if panel.frame.contains(point) {
            return super.hitTest(point, with: event)
        }
        return nil
    }
}

private final class RoomsSheetController<Content: View>: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private var collapsedTopInset: CGFloat
    private let expandedTop: CGFloat = 8

    private let panel = UIView()
    private let grabber = UIView()
    private let hairline = UIView()
    private let scrollView = NonAutoScrollingScrollView()

    private let hostingController: UIHostingController<Content>
    private var topConstraint: NSLayoutConstraint!

    private var lastPanY: CGFloat = 0
    private var contentSizeObservation: NSKeyValueObservation?

    /// Reports expand progress (0 = collapsed, 1 = expanded) — emitted from the pan and from the
    /// settle display link so the SwiftUI header tracks the panel frame-perfectly.
    var onProgress: ((CGFloat) -> Void)?
    /// Last progress we emitted, so we don't spam identical values.
    private var lastEmittedProgress: CGFloat = -1

    /// Self-driven settle: one display link springs `topConstraint.constant` toward `settleTarget`
    /// each frame and emits progress from the same value. Because the constraint always holds the
    /// real on-screen position (no UIView.animate model-jump), a new pan can interrupt mid-settle
    /// with no jump — just stop the link.
    private var settleLink: CADisplayLink?
    private var settleTarget: CGFloat = 0
    private var settleVelocity: CGFloat = 0

    #if DEBUG
    private let debugLabel = UILabel()
    private func updateDebug() {
        debugLabel.text = String(
            format: "top=%.0f exp=%@ off=%.0f csize=%.0f bounds=%.0f sframe=%.0f",
            topConstraint?.constant ?? -1,
            isExpanded ? "Y" : "N",
            scrollView.contentOffset.y,
            scrollView.contentSize.height,
            scrollView.bounds.height,
            scrollView.frame.minY
        )
    }
    #endif

    private var collapsedTop: CGFloat { collapsedTopInset }

    init(collapsedTopInset: CGFloat, panelBackground: UIColor, grabberColor: UIColor, hairlineColor: UIColor, content: Content) {
        self.collapsedTopInset = collapsedTopInset
        self.hostingController = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
        panel.backgroundColor = panelBackground
        grabber.backgroundColor = grabberColor
        hairline.backgroundColor = hairlineColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = PassthroughView()
        root.backgroundColor = .clear
        root.panel = panel
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Panel
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = 32
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.layer.cornerCurve = .continuous
        view.addSubview(panel)

        topConstraint = panel.topAnchor.constraint(equalTo: view.topAnchor, constant: collapsedTop)
        NSLayoutConstraint.activate([
            topConstraint,
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Extend below the screen so the panel always reaches the bottom edge (behind tab bar).
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 1000),
        ])

        // Hairline at the very top edge of the panel
        hairline.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: panel.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // Grabber
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.layer.cornerRadius = 2.5
        panel.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            grabber.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 40),
            grabber.heightAnchor.constraint(equalToConstant: 5),
        ])

        // Scroll view + hosted SwiftUI content
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        panel.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: panel.topAnchor, constant: 25),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Keep the hosting view's intrinsic size in sync with the SwiftUI content. Without this the
        // self-sizing scroll view measures the content once and never grows when rooms load async,
        // so `contentSize` stays too short, the VStack overflows its frame and SwiftUI centers the
        // overflow — clipping the header and first row at the top (the reported bug).
        hostingController.sizingOptions = .intrinsicContentSize
        // Stop the hosting controller from injecting a safe-area inset into the content (it would
        // push the list down and cut off the bottom, since the panel sits near the screen top).
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hostingController)
        scrollView.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // One pan gesture on the panel, coordinated with the scroll view's own pan.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        panel.addGestureRecognizer(pan)

        // When the content grows (async room load re-renders the hosted SwiftUI), keep the list
        // pinned to the top while collapsed — content-size changes don't emit a scroll event, so
        // scrollViewDidScroll alone misses them (this was the "scrolled-down / first row clipped" bug).
        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] sv, _ in
            guard let self else { return }
            
            // Lock to the top on dynamic content size changes UNLESS the user is actively scrolling.
            guard !sv.isTracking, !sv.isDragging, !sv.isDecelerating, !self.isPanning else { return }
            
            if sv.contentOffset.y != 0 {
                sv.contentOffset.y = 0
            }
        }

        #if DEBUG
        debugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        debugLabel.textColor = .yellow
        debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        debugLabel.numberOfLines = 1
        debugLabel.adjustsFontSizeToFitWidth = true
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugLabel)
        NSLayoutConstraint.activate([
            debugLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            debugLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            debugLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
        ])
        #endif
    }

    private var isPanning = false
    /// Did the current gesture actually move the panel (vs. purely scroll the list)? Only a gesture
    /// that moved the panel gets a velocity-driven settle on release — otherwise a fast content
    /// overscroll fling would bleed into the panel spring and jolt it instead of bouncing the list.
    private var didMovePanel = false
    /// True for the lifetime of a pan that began while collapsed. Such a gesture only ever drives the
    /// panel to its detent — it never hands its leftover fling off to scrolling, even after the panel
    /// reaches full-expand mid-gesture. Scrolling starts on the next, separate touch.
    private var gestureLocksScroll = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Keep the scroll view's "may scroll" state in sync with the current detent every layout
        // pass — this is the single source of truth the scroll view uses to hard-pin the top.
        syncScrollEnabled()

        // Defend against any initial or post-load offset while collapsed and not interacting.
        if !scrollView.allowsContentScroll && !scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating && !isPanning {
            if scrollView.contentOffset.y != 0 {
                scrollView.contentOffset.y = 0
            }
        }

        #if DEBUG
        view.bringSubviewToFront(debugLabel)
        updateDebug()
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The very first presented frame can land after a layout pass that nudged the offset
        // during the async room load. Re-pin the top once on appear while collapsed.
        if !isExpanded {
            scrollView.contentOffset.y = 0
        }
    }

    /// Content may scroll only when the panel is expanded; while collapsed the scroll view stays
    /// hard-pinned to the top (see `NonAutoScrollingScrollView`).
    private func syncScrollEnabled() {
        scrollView.allowsContentScroll = isExpanded && !gestureLocksScroll
    }

    func update(collapsedTopInset: CGFloat, panelBackground: UIColor, grabberColor: UIColor, hairlineColor: UIColor, content: Content) {
        hostingController.rootView = content
        panel.backgroundColor = panelBackground
        grabber.backgroundColor = grabberColor
        hairline.backgroundColor = hairlineColor
        // After the content swap settles, keep the list at the top while collapsed.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isExpanded, !self.isPanning else { return }
            if self.scrollView.contentOffset.y != 0 { self.scrollView.contentOffset.y = 0 }
        }
        if self.collapsedTopInset != collapsedTopInset {
            self.collapsedTopInset = collapsedTopInset
            // Keep the panel collapsed-aligned if it's resting collapsed.
            if abs(topConstraint.constant - expandedTop) > 0.5 {
                topConstraint.constant = collapsedTopInset
            }
        }
    }

    private var isExpanded: Bool { topConstraint.constant <= expandedTop + 0.5 }

    // MARK: - Header progress

    /// Maps a panel top-offset to 0 (collapsed) … 1 (expanded), clamped.
    private func progress(forTop top: CGFloat) -> CGFloat {
        let span = collapsedTop - expandedTop
        guard span > 0 else { return 0 }
        return min(1, max(0, (collapsedTop - top) / span))
    }

    /// Emit a progress value to the header, de-duplicated.
    private func emitProgress(_ p: CGFloat) {
        guard abs(p - lastEmittedProgress) > 0.0001 else { return }
        lastEmittedProgress = p
        onProgress?(p)
    }

    // MARK: - Pan coordination

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let translationY = g.translation(in: panel).y
        switch g.state {
        case .began:
            lastPanY = 0
            isPanning = true
            scrollView.isPanningSheet = true
            // Lock scrolling for this whole gesture if it started collapsed: it should only expand the
            // panel, not flow into scrolling the list.
            gestureLocksScroll = !isExpanded
            didMovePanel = false
            // A new drag overrides any in-flight settle. The constraint already holds the real
            // on-screen position (we drive it each frame), so the next .changed picks up with no jump.
            stopSettle()
        case .changed:
            let dy = translationY - lastPanY
            lastPanY = translationY
            let top = topConstraint.constant
            let atTop = scrollView.contentOffset.y <= 0
            // Move the panel while resizing, or when expanded + at the top + pulling down.
            let movePanel = (top > expandedTop) || (atTop && dy > 0)
            if movePanel {
                didMovePanel = true
                topConstraint.constant = min(collapsedTop, max(expandedTop, top + dy))
                // Pin the scroll to the top so content doesn't move while the panel resizes.
                scrollView.contentOffset.y = 0
                syncScrollEnabled()
                // Header follows the finger live.
                emitProgress(progress(forTop: topConstraint.constant))
            }
        case .ended, .cancelled:
            isPanning = false
            scrollView.isPanningSheet = false
            gestureLocksScroll = false // gesture over; the next touch decides scroll afresh
            // Only spring the panel if this gesture moved it. A pure content-scroll gesture leaves the
            // panel at its detent — settling it with the scroll fling velocity would jolt it and rob
            // the list of its native overscroll bounce.
            guard didMovePanel else { break }
            let velocityY = g.velocity(in: panel).y
            let projected = topConstraint.constant + velocityY * 0.12
            let mid = (expandedTop + collapsedTop) / 2
            let target = projected < mid ? expandedTop : collapsedTop
            settle(to: target, velocityY: velocityY)
        default:
            isPanning = false
            scrollView.isPanningSheet = false
            gestureLocksScroll = false
        }
    }

    /// Spring the panel to `target`, carrying the fling velocity. Critically damped, so it eases in
    /// without overshoot. The display link (`settleTick`) advances the constraint each frame.
    private func settle(to target: CGFloat, velocityY: CGFloat) {
        settleTarget = target
        settleVelocity = velocityY
        // The target detent decides whether content may scroll; update up front so the scroll view
        // pins (collapsed) or releases (expanded) immediately.
        syncScrollEnabled()
        if settleLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(settleTick(_:)))
            link.add(to: .main, forMode: .common)
            settleLink = link
        }
    }

    private func stopSettle() {
        settleLink?.invalidate()
        settleLink = nil
    }

    @objc private func settleTick(_ link: CADisplayLink) {
        let dt = CGFloat(link.duration)
        // Critically damped spring: damping = 2·√stiffness ⇒ fast, no overshoot. Bump `stiffness`
        // for a snappier settle. Integrated semi-implicitly for stability at high fling speeds.
        let stiffness: CGFloat = 220
        let damping = 2 * sqrt(stiffness)
        let x = topConstraint.constant
        settleVelocity += (-stiffness * (x - settleTarget) - damping * settleVelocity) * dt
        var next = x + settleVelocity * dt

        // Close enough — snap to the exact detent and finish.
        if abs(next - settleTarget) < 0.5 && abs(settleVelocity) < 5 {
            next = settleTarget
            stopSettle()
        }
        topConstraint.constant = next
        view.layoutIfNeeded()
        emitProgress(progress(forTop: next))
    }

    deinit { settleLink?.invalidate() }

    // MARK: - Delegates

    // Keep the content pinned at the top while the panel isn't fully expanded — or for the whole of a
    // gesture that began collapsed — so the scroll view's own pan can't move content during a resize
    // (prevents the two-system "shake") or flow a fast open-flick straight into scrolling.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if (!isExpanded || gestureLocksScroll) && scrollView.contentOffset.y != 0 {
            scrollView.contentOffset.y = 0
        }
        #if DEBUG
        updateDebug()
        #endif
    }

    // Run our pan alongside the scroll view's pan so one drag drives both.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
