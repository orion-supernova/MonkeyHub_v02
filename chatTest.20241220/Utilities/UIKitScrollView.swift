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
    private var isProgrammaticScroll = false
    private var isUpdatingContent = false
    private var hasHadScrollableContent = false
    private var shouldAutoFollowBottom = true
    private let bottomStateThreshold: CGFloat = 100
    private let autoFollowThreshold: CGFloat = 140
    private var lastViewportHeight: CGFloat = 0
    private var lastDragOffsetY: CGFloat = 0
    private var keyboardAnimationDuration: TimeInterval = 0.25
    private var isKeyboardAnimating = false
    private var currentKeyboardHeight: CGFloat = 0
    private var baselineSafeAreaBottom: CGFloat = 0
    private var isInteractiveKeyboardDismissInProgress = false
    private var shouldMaintainBottomDuringKeyboardInteraction = false

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
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        let wasNearBottom = isNearBottom(threshold: autoFollowThreshold)
        wasAtBottomBeforeKeyboard = wasNearBottom
        shouldMaintainBottomDuringKeyboardInteraction = wasNearBottom || shouldAutoFollowBottom
        isInteractiveKeyboardDismissInProgress = false
        baselineSafeAreaBottom = view.window?.safeAreaInsets.bottom ?? 0
        
        // Blocking layout snaps early prevents the flicker when focus changes.
        isKeyboardAnimating = true
        isProgrammaticScroll = true
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        if !isInteractiveKeyboardDismissInProgress {
            shouldMaintainBottomDuringKeyboardInteraction = isNearBottom(threshold: autoFollowThreshold) || shouldAutoFollowBottom
        }
        isKeyboardAnimating = true
        isProgrammaticScroll = true
        currentKeyboardHeight = 0
        applyInsets(
            maintainBottomIfNeeded: shouldMaintainBottomDuringKeyboardInteraction,
            forceInsetUpdate: true
        )
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
        
        // Capture the initial home-indicator / bottom safe area if we haven't yet.
        // This fixes the 'initial space too small' issue when first opening a room.
        if baselineSafeAreaBottom == 0, let window = view.window {
            baselineSafeAreaBottom = window.safeAreaInsets.bottom
            applyInsets(maintainBottomIfNeeded: true)
        }

        hasHadScrollableContent = hasHadScrollableContent || isScrollable()
        
        if lastViewportHeight > 0,
           shouldAutoFollowBottom,
           !scrollView.isDragging,
           !scrollView.isDecelerating {
            scheduleScrollToBottomAfterLayout(animated: false)
        }
        lastViewportHeight = scrollView.bounds.height

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
            shouldAutoFollowBottom = true
        }

        let shouldStickToBottom = shouldAutoFollowBottom && itemCount > 0

        if wasPrepended && !shouldAutoFollowBottom {
            preservePositionDuringUpdate(content: content)
        } else {
            updateContent(
                content,
                scrollToBottomIfNeeded: transitionedFromEmpty || (shouldStickToBottom && itemCountIncreased),
                forceInitialAnchor: transitionedFromEmpty,
                animatedScroll: !transitionedFromEmpty && !wasPrepended && itemCountIncreased
            )
        }
    }

    func updateContent(
        _ content: Content,
        scrollToBottomIfNeeded: Bool = false,
        forceInitialAnchor: Bool = false,
        animatedScroll: Bool = true
    ) {
        hostingController.rootView = content
        
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        if forceInitialAnchor {
            scheduleScrollToBottomAfterLayout(animated: false)
        } else if scrollToBottomIfNeeded {
            scheduleScrollToBottomAfterLayout(animated: animatedScroll)
        } else {
            if scrollView.contentOffset.y < -baseTopInset {
                scrollView.contentOffset.y = -baseTopInset
            }
        }
    }

    private func performImmediateScrollToBottom(animated: Bool) {
        scrollView.layoutIfNeeded()
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height
        let btmInset = scrollView.contentInset.bottom
        let targetY = max(-baseTopInset, contentHeight - frameHeight + btmInset)
        
        if abs(scrollView.contentOffset.y - targetY) < 0.5 {
            return
        }
        
        performProgrammaticScroll(animated: animated) {
            self.scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        }
    }

    private func applyInsets(maintainBottomIfNeeded: Bool = true, forceInsetUpdate: Bool = false) {
        let dynamicBottom = max(currentKeyboardHeight, baselineSafeAreaBottom)
        let totalBottomInset = baseBottomInset + dynamicBottom

        let newInsets = UIEdgeInsets(
            top: baseTopInset,
            left: 0,
            bottom: totalBottomInset,
            right: 0
        )

        if scrollView.contentInset != newInsets, (!isKeyboardAnimating || forceInsetUpdate) {
            scrollView.contentInset = newInsets
            scrollView.scrollIndicatorInsets = newInsets
            
            if scrollView.contentOffset.y == 0 && baseTopInset > 0 {
                scrollView.contentOffset.y = -baseTopInset
            }
        }

        minContentHeightConstraint?.constant = -(baseTopInset + totalBottomInset)

        if forceInsetUpdate {
            adjustContentOffsetForCurrentInsets(maintainBottom: maintainBottomIfNeeded)
        }

        if maintainBottomIfNeeded && shouldAutoFollowBottom && !scrollView.isDragging && !scrollView.isDecelerating {
            if distanceFromBottom() > -1 {
                scheduleScrollToBottomAfterLayout(animated: false)
            }
        }
    }

    private func adjustContentOffsetForCurrentInsets(maintainBottom: Bool) {
        let minOffsetY = -scrollView.contentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        )
        let targetOffsetY = maintainBottom ? maxOffsetY : min(max(scrollView.contentOffset.y, minOffsetY), maxOffsetY)

        guard abs(scrollView.contentOffset.y - targetOffsetY) > 0.5 else { return }
        scrollView.contentOffset.y = targetOffsetY
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = view.window else { return }

        if let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
           duration > 0 {
            keyboardAnimationDuration = duration
        }

        let keyboardVisibleHeight = max(0, window.bounds.maxY - endFrame.minY)
        let wasKeyboardVisible = currentKeyboardHeight > 0
        let keyboardIsMovingDown = keyboardVisibleHeight < currentKeyboardHeight
        currentKeyboardHeight = keyboardVisibleHeight

        if scrollView.isDragging && (wasKeyboardVisible || keyboardVisibleHeight > 0) {
            isInteractiveKeyboardDismissInProgress = true
        }

        if isInteractiveKeyboardDismissInProgress && keyboardIsMovingDown {
            applyInsets(
                maintainBottomIfNeeded: shouldMaintainBottomDuringKeyboardInteraction,
                forceInsetUpdate: true
            )

            if keyboardVisibleHeight == 0 && !scrollView.isTracking && !scrollView.isDecelerating {
                finishInteractiveKeyboardDismissIfNeeded()
            } else {
                publishAtBottomStateIfNeeded()
            }
            return
        }
        
        let shouldAnchorForKeyboard = (keyboardVisibleHeight > 0)
            ? (wasAtBottomBeforeKeyboard || shouldAutoFollowBottom)
            : shouldAutoFollowBottom
            
        if shouldAnchorForKeyboard && !scrollView.isDragging && !scrollView.isDecelerating {
            shouldAutoFollowBottom = true
            animateScrollToMatchKeyboard(targetKeyboardHeight: keyboardVisibleHeight)
        } else {
            isKeyboardAnimating = true
            isProgrammaticScroll = true
            
            UIView.animate(withDuration: keyboardAnimationDuration) {
                self.applyInsets(maintainBottomIfNeeded: false)
            } completion: { _ in
                self.shouldScrollToBottomAfterLayout = false
                self.pendingScrollToBottomAnimated = false
                self.isKeyboardAnimating = false
                self.isProgrammaticScroll = false
                self.applyInsets(maintainBottomIfNeeded: false)
                self.publishAtBottomStateIfNeeded()
            }
        }
    }

    private func animateScrollToMatchKeyboard(targetKeyboardHeight: CGFloat) {
        isKeyboardAnimating = true
        isProgrammaticScroll = true
        
        let finalDynamicBottom = max(targetKeyboardHeight, baselineSafeAreaBottom)
        let finalTotalInset = baseBottomInset + finalDynamicBottom
        let targetY = max(-baseTopInset, scrollView.contentSize.height - scrollView.bounds.height + finalTotalInset)

        UIView.animate(
            withDuration: keyboardAnimationDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.scrollView.contentInset.bottom = finalTotalInset
            self.scrollView.scrollIndicatorInsets.bottom = finalTotalInset
            self.scrollView.contentOffset.y = targetY
        } completion: { [weak self] _ in
            guard let self = self else { return }
            self.shouldScrollToBottomAfterLayout = false
            self.pendingScrollToBottomAnimated = false
            self.isKeyboardAnimating = false
            self.isProgrammaticScroll = false
            self.applyInsets(maintainBottomIfNeeded: false)
            self.scheduleScrollToBottomAfterLayout(animated: false)
            self.publishAtBottomStateIfNeeded()
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
            performProgrammaticScroll(animated: false) {
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
        guard !isKeyboardAnimating else { return }
        guard shouldScrollToBottomAfterLayout else { return }
        guard !scrollView.isDragging, !scrollView.isDecelerating else { return }
        
        shouldScrollToBottomAfterLayout = false
        let animated = pendingScrollToBottomAnimated
        pendingScrollToBottomAnimated = false
        self.performImmediateScrollToBottom(animated: animated)
        publishAtBottomStateIfNeeded()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if isKeyboardAnimating {
            scrollView.layer.removeAllAnimations()
            isKeyboardAnimating = false
            isProgrammaticScroll = false
        }
        if currentKeyboardHeight > 0 {
            isInteractiveKeyboardDismissInProgress = true
            shouldMaintainBottomDuringKeyboardInteraction = isNearBottom(threshold: autoFollowThreshold)
        }
        shouldScrollToBottomAfterLayout = false
        pendingScrollToBottomAnimated = false
        lastDragOffsetY = scrollView.contentOffset.y
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            finishInteractiveKeyboardDismissIfNeeded()
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
        publishAtBottomStateIfNeeded()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishInteractiveKeyboardDismissIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height

        hasHadScrollableContent = hasHadScrollableContent || contentHeight > frameHeight + 1
        if isInteractiveKeyboardDismissInProgress {
            if scrollView.isDragging && offsetY < (lastDragOffsetY - 0.5) {
                shouldMaintainBottomDuringKeyboardInteraction = false
                shouldAutoFollowBottom = false
            }
            lastDragOffsetY = offsetY
        } else if scrollView.isDragging {
            if offsetY < (lastDragOffsetY - 0.5) {
                shouldAutoFollowBottom = false
            }
            lastDragOffsetY = offsetY
        } else if scrollView.isDecelerating {
            if !isNearBottom(threshold: autoFollowThreshold) {
                shouldAutoFollowBottom = false
            }
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

    private func performProgrammaticScroll(animated: Bool, _ action: () -> Void) {
        isProgrammaticScroll = true
        action()
        if !animated {
            isProgrammaticScroll = false
            publishAtBottomStateIfNeeded()
        }
    }

    private func publishAtBottomStateIfNeeded() {
        let isAtBottomNow = isAtBottom()
        if isAtBottomNow {
            shouldAutoFollowBottom = true
        }
        guard isAtBottomNow != lastAtBottomState else { return }
        lastAtBottomState = isAtBottomNow
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isUpdatingContent else { return }
            self.onAtBottomChanged?(isAtBottomNow)
        }
    }

    private func isScrollable() -> Bool {
        scrollView.contentSize.height > scrollView.bounds.height + 1
    }

    private func finishInteractiveKeyboardDismissIfNeeded() {
        guard isInteractiveKeyboardDismissInProgress else { return }

        isInteractiveKeyboardDismissInProgress = false
        shouldAutoFollowBottom = shouldMaintainBottomDuringKeyboardInteraction && isNearBottom(threshold: autoFollowThreshold)

        if shouldAutoFollowBottom {
            scheduleScrollToBottomAfterLayout(animated: false)
        }

        publishAtBottomStateIfNeeded()
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
