import SwiftUI

#if canImport(UIKit)
import UIKit

struct UIKitScrollView<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let firstItemId: String?
    let itemCount: Int
    let topInset: CGFloat
    let bottomInset: CGFloat
    @Binding var scrollToBottom: Bool
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIKitScrollViewController<Content> {
        let vc = UIKitScrollViewController(content: content)
        vc.onNearTop = onNearTop
        vc.onAtBottomChanged = onAtBottomChanged
        vc.setBaseInsets(top: topInset, bottom: bottomInset)
        return vc
    }

    func updateUIViewController(_ vc: UIKitScrollViewController<Content>, context: Context) {
        let wasPrepended = vc.lastFirstItemId != nil && firstItemId != nil &&
                          vc.lastFirstItemId != firstItemId && itemCount > vc.lastItemCount
        let itemCountIncreased = itemCount > vc.lastItemCount
        let transitionedFromEmpty = vc.lastItemCount == 0 && itemCount > 0

        vc.setBaseInsets(top: topInset, bottom: bottomInset)

        vc.applyUpdate(
            content: content,
            firstItemId: firstItemId,
            itemCount: itemCount,
            wasPrepended: wasPrepended,
            itemCountIncreased: itemCountIncreased,
            transitionedFromEmpty: transitionedFromEmpty
        )

        if scrollToBottom {
            DispatchQueue.main.async {
                vc.requestScrollToBottom(animated: true)
                self.scrollToBottom = false
            }
        }
    }
}

final class UIKitScrollViewController<Content: View>: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.backgroundColor = .clear
        sv.keyboardDismissMode = .interactive
        sv.contentInsetAdjustmentBehavior = .never
        return sv
    }()

    var hostingController: UIHostingController<Content>!
    private let contentContainerView = UIView()
    private var minContentHeightConstraint: NSLayoutConstraint?
    var lastFirstItemId: String?
    var lastItemCount: Int = 0
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?
    private var hasTriggeredNearTop = false
    private var lastAtBottomState = true
    private var wasAtBottomBeforeKeyboard = true
    private var shouldScrollToBottomAfterLayout = false
    private var pendingScrollToBottomAnimated = false
    private var baseTopInset: CGFloat = 0
    private var baseBottomInset: CGFloat = 0
    private var keyboardInset: CGFloat = 0
    private var isProgrammaticScroll = false
    private var isUpdatingContent = false
    private var hasHadScrollableContent = false
    private var shouldAutoFollowBottom = true
    private let bottomStateThreshold: CGFloat = 100
    private let autoFollowThreshold: CGFloat = 140

    init(content: Content) {
        super.init(nibName: nil, bundle: nil)
        self.hostingController = UIHostingController(rootView: content)
        self.hostingController.sizingOptions = [.intrinsicContentSize]
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        setupHostingController()
        setupKeyboardObservers()
        setupKeyboardDismissGesture()
        applyInsets()
    }

    private func setupKeyboardDismissGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToDismissKeyboard(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        scrollView.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTapToDismissKeyboard(_ gesture: UITapGestureRecognizer) {
        view.window?.endEditing(true)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        wasAtBottomBeforeKeyboard = isAtBottom()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard notification.userInfo != nil else { return }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if isAtBottom() {
            scheduleScrollToBottomAfterLayout(animated: false)

            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.publishAtBottomStateIfNeeded()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hasHadScrollableContent = hasHadScrollableContent || isScrollable()

        if shouldScrollToBottomAfterLayout {
            flushPendingScrollToBottomIfNeeded()
        }
    }

    private func isAtBottom() -> Bool {
        isNearBottom(threshold: bottomStateThreshold)
    }

    private func isNearBottom(threshold: CGFloat) -> Bool {
        distanceFromBottom() <= threshold
    }

    private func distanceFromBottom() -> CGFloat {
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height
        let offsetY = scrollView.contentOffset.y
        let bottomInset = scrollView.contentInset.bottom
        return contentHeight - (offsetY + frameHeight - bottomInset)
    }

    private func setupScrollView() {
        view.addSubview(scrollView)
        scrollView.delegate = self
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupHostingController() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = .clear
        scrollView.addSubview(contentContainerView)

        minContentHeightConstraint = contentContainerView.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
        )

        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentContainerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            minContentHeightConstraint!
        ])

        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hostingController)
        contentContainerView.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            hostingController.view.topAnchor.constraint(greaterThanOrEqualTo: contentContainerView.topAnchor)
        ])
    }

    func setBaseInsets(top: CGFloat, bottom: CGFloat) {
        baseTopInset = top
        baseBottomInset = bottom
        applyInsets()
    }

    func applyUpdate(
        content: Content,
        firstItemId: String?,
        itemCount: Int,
        wasPrepended: Bool,
        itemCountIncreased: Bool,
        transitionedFromEmpty: Bool
    ) {
        isUpdatingContent = true
        defer {
            lastFirstItemId = firstItemId
            lastItemCount = itemCount
            isUpdatingContent = false
        }

        if transitionedFromEmpty {
            // Fresh room entry starts in "follow bottom" mode.
            shouldAutoFollowBottom = true
        }

        let shouldStickToBottom = shouldAutoFollowBottom && itemCount > 0

        if wasPrepended && !shouldAutoFollowBottom {
            preservePositionDuringUpdate(content: content)
        } else {
            updateContent(
                content,
                scrollToBottomIfNeeded: transitionedFromEmpty || shouldStickToBottom,
                forceInitialAnchor: transitionedFromEmpty,
                animatedScroll: !transitionedFromEmpty && !wasPrepended && itemCountIncreased
            )
        }
    }

    // UIKitScrollView.swift -> Inside UIKitScrollViewController class

    func updateContent(
        _ content: Content,
        scrollToBottomIfNeeded: Bool = false,
        forceInitialAnchor: Bool = false,
        animatedScroll: Bool = true
    ) {
        hostingController.rootView = content
        
        // FORCE LAYOUT: We must tell the hosting view and the scrollview to
        // update their geometry NOW so contentSize is accurate.
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        if forceInitialAnchor {
            // FIRST NON-EMPTY LOAD:
            // Chat rooms should open on the latest message, but the content
            // size is not stable until UIKit finishes laying out the hosted
            // SwiftUI view. Defer the initial anchor until that layout settles.
            scheduleScrollToBottomAfterLayout(animated: false)
        } else if scrollToBottomIfNeeded {
            scheduleScrollToBottomAfterLayout(animated: animatedScroll)
        } else {
            // PREVENT OVERLAP ON SHORT LISTS:
            // If content is shorter than the screen, ensure it doesn't
            // snap back behind the top controls.
            if scrollView.contentOffset.y < -baseTopInset {
                scrollView.contentOffset.y = -baseTopInset
            }
        }
    }

    private func performImmediateScrollToBottom(animated: Bool) {
        // Re-verify layout before calculating bottom
        scrollView.layoutIfNeeded()
        
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height
        let btmInset = scrollView.contentInset.bottom
        
        // Calculate bottom Y.
        // We max with -baseTopInset so the list never scrolls "up" into the header.
        let targetY = max(-baseTopInset, contentHeight - frameHeight + btmInset)
        
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
    }

    private func applyInsets(maintainBottomIfNeeded: Bool = true) {
        let wasNearBottom = isNearBottom(threshold: autoFollowThreshold)
        let totalBottomInset = baseBottomInset + keyboardInset
        
        let newInsets = UIEdgeInsets(
            top: baseTopInset,
            left: 0,
            bottom: totalBottomInset,
            right: 0
        )
        
        if scrollView.contentInset != newInsets {
            scrollView.contentInset = newInsets
            scrollView.scrollIndicatorInsets = newInsets
            
            // If the scrollview is currently "idle" at 0,
            // force it to sit at the top inset position.
            if scrollView.contentOffset.y == 0 && baseTopInset > 0 {
                scrollView.contentOffset.y = -baseTopInset
            }
        }

        minContentHeightConstraint?.constant = -(baseTopInset + totalBottomInset)

        if maintainBottomIfNeeded && (shouldAutoFollowBottom || wasNearBottom) {
            scheduleScrollToBottomAfterLayout(animated: false)
        }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let animationCurve = UIView.AnimationOptions(rawValue: curveValue << 16)
        let overlap = keyboardOverlap(for: endFrame)

        UIView.animate(withDuration: duration, delay: 0, options: [animationCurve, .beginFromCurrentState]) {
            self.keyboardInset = overlap
            self.applyInsets(maintainBottomIfNeeded: false)
            
            // Keep anchored only when user was already following bottom.
            if self.wasAtBottomBeforeKeyboard || self.shouldAutoFollowBottom {
                self.performImmediateScrollToBottom(animated: false)
            }
        }
    }

    func preservePositionDuringUpdate(content: Content) {
        let oldHeight = scrollView.contentSize.height
        let oldOffset = scrollView.contentOffset.y
        hostingController.rootView = content
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        let delta = scrollView.contentSize.height - oldHeight
        if delta > 0 {
            performProgrammaticScroll {
                self.scrollView.contentOffset.y = oldOffset + delta
            }
        }
    }

    func requestScrollToBottom(animated: Bool) {
        scheduleScrollToBottomAfterLayout(animated: animated)
    }

    private func scheduleScrollToBottomAfterLayout(animated: Bool) {
        shouldScrollToBottomAfterLayout = true
        pendingScrollToBottomAnimated = pendingScrollToBottomAnimated || animated
        view.setNeedsLayout()
        scrollView.setNeedsLayout()
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingScrollToBottomIfNeeded()
        }
    }

    private func flushPendingScrollToBottomIfNeeded() {
        guard shouldScrollToBottomAfterLayout else { return }
        shouldScrollToBottomAfterLayout = false
        let animated = pendingScrollToBottomAnimated
        pendingScrollToBottomAnimated = false
        performProgrammaticScroll {
            self.performImmediateScrollToBottom(animated: animated)
        }
        publishAtBottomStateIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height

        hasHadScrollableContent = hasHadScrollableContent || contentHeight > frameHeight + 1
        if scrollView.isDragging || scrollView.isDecelerating {
            shouldAutoFollowBottom = isNearBottom(threshold: autoFollowThreshold)
        }

        guard !isUpdatingContent, !isProgrammaticScroll else { return }

        if offsetY <= 150 &&
            contentHeight > frameHeight &&
            hasHadScrollableContent &&
            (scrollView.isDragging || scrollView.isDecelerating) {
            if !hasTriggeredNearTop {
                hasTriggeredNearTop = true
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isUpdatingContent, !self.isProgrammaticScroll else { return }
                    self.onNearTop?()
                }
            }
        } else if offsetY > 200 {
            hasTriggeredNearTop = false
        }

        let isAtBottom = isNearBottom(threshold: bottomStateThreshold)
        if isAtBottom != lastAtBottomState {
            lastAtBottomState = isAtBottom
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isUpdatingContent, !self.isProgrammaticScroll else { return }
                self.onAtBottomChanged?(isAtBottom)
            }
        }
    }

    private func keyboardOverlap(for endFrame: CGRect) -> CGFloat {
        guard let window = view.window else { return 0 }
        let scrollFrameInWindow = scrollView.convert(scrollView.bounds, to: window)
        
        // If the keyboard is hidden (endFrame at bottom of screen), overlap is 0
        let overlap = max(0, scrollFrameInWindow.maxY - endFrame.origin.y)
        return overlap
    }

    private func performProgrammaticScroll(_ action: () -> Void) {
        isProgrammaticScroll = true
        action()
        DispatchQueue.main.async { [weak self] in
            self?.isProgrammaticScroll = false
        }
    }

    private func publishAtBottomStateIfNeeded() {
        let isAtBottomNow = isAtBottom()
        guard isAtBottomNow != lastAtBottomState else { return }
        lastAtBottomState = isAtBottomNow
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isUpdatingContent, !self.isProgrammaticScroll else { return }
            self.onAtBottomChanged?(isAtBottomNow)
        }
    }

    private func isScrollable() -> Bool {
        scrollView.contentSize.height > scrollView.bounds.height + 1
    }
}

#elseif canImport(AppKit)
import AppKit

// MARK: - macOS Implementation using AppKit
struct UIKitScrollView<Content: View>: NSViewControllerRepresentable {
    let content: Content
    let firstItemId: String?
    let itemCount: Int
    let topInset: CGFloat
    let bottomInset: CGFloat
    @Binding var scrollToBottom: Bool
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?

    func makeNSViewController(context: Context) -> MacScrollViewController<Content> {
        let vc = MacScrollViewController(content: content)
        vc.onNearTop = onNearTop
        vc.onAtBottomChanged = onAtBottomChanged
        return vc
    }

    func updateNSViewController(_ vc: MacScrollViewController<Content>, context: Context) {
        let wasPrepended = vc.lastFirstItemId != nil && firstItemId != nil &&
                          vc.lastFirstItemId != firstItemId && itemCount > vc.lastItemCount

        if wasPrepended {
            vc.preservePositionDuringUpdate(content: content)
        } else {
            vc.updateContent(content)
        }

        vc.lastFirstItemId = firstItemId
        vc.lastItemCount = itemCount

        if scrollToBottom {
            DispatchQueue.main.async {
                vc.scrollToBottom(animated: true)
                self.scrollToBottom = false
            }
        }
    }
}

final class MacScrollViewController<Content: View>: NSViewController {
    private var scrollView: NSScrollView!
    private var hostingView: NSHostingView<Content>!

    var lastFirstItemId: String?
    var lastItemCount: Int = 0
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?

    private var didInitialScroll = false
    private var hasTriggeredNearTop = false
    private var lastAtBottomState = true
    private var contentSizeObservation: NSKeyValueObservation?

    init(content: Content) {
        super.init(nibName: nil, bundle: nil)
        self.hostingView = NSHostingView(rootView: content)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        // Configure the hosting view
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Create a flipped clip view for natural top-to-bottom content
        let clipView = FlippedClipView()
        clipView.documentView = hostingView
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        // Set constraints for hosting view width
        NSLayoutConstraint.activate([
            hostingView.widthAnchor.constraint(equalTo: clipView.widthAnchor)
        ])

        self.view = scrollView

        // Observe scroll position
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )

        // Observe content size changes for initial scroll
        contentSizeObservation = hostingView.observe(\.fittingSize, options: [.new]) { [weak self] _, _ in
            guard let self = self else { return }
            if !self.didInitialScroll {
                DispatchQueue.main.async {
                    self.didInitialScroll = true
                    self.scrollToBottom(animated: false)
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard let clipView = scrollView.contentView as? NSClipView else { return }

        let offsetY = clipView.bounds.origin.y
        let contentHeight = hostingView.fittingSize.height
        let frameHeight = scrollView.bounds.height

        // Near top detection
        if offsetY <= 150 && contentHeight > frameHeight {
            if !hasTriggeredNearTop {
                hasTriggeredNearTop = true
                DispatchQueue.main.async { [weak self] in
                    self?.onNearTop?()
                }
            }
        } else if offsetY > 200 {
            hasTriggeredNearTop = false
        }

        // At bottom detection
        let distanceFromBottom = contentHeight - (offsetY + frameHeight)
        let isAtBottom = distanceFromBottom <= 100
        if isAtBottom != lastAtBottomState {
            lastAtBottomState = isAtBottom
            DispatchQueue.main.async { [weak self] in
                self?.onAtBottomChanged?(isAtBottom)
            }
        }
    }

    func updateContent(_ content: Content) {
        hostingView.rootView = content
    }

    func preservePositionDuringUpdate(content: Content) {
        guard let clipView = scrollView.contentView as? NSClipView else {
            updateContent(content)
            return
        }

        let oldHeight = hostingView.fittingSize.height
        let oldOffset = clipView.bounds.origin.y

        hostingView.rootView = content
        hostingView.layoutSubtreeIfNeeded()

        let delta = hostingView.fittingSize.height - oldHeight
        if delta > 0 {
            clipView.scroll(to: NSPoint(x: 0, y: oldOffset + delta))
        }
    }

    func scrollToBottom(animated: Bool) {
        guard let clipView = scrollView.contentView as? NSClipView else { return }

        let contentHeight = hostingView.fittingSize.height
        let frameHeight = scrollView.bounds.height
        let maxOffsetY = max(0, contentHeight - frameHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                clipView.scroll(to: NSPoint(x: 0, y: maxOffsetY))
            }
        } else {
            clipView.scroll(to: NSPoint(x: 0, y: maxOffsetY))
        }
        scrollView.reflectScrolledClipView(clipView)
    }
}

// Flipped clip view for proper scroll behavior (content starts at top)
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

#endif
