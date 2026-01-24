import SwiftUI

#if canImport(UIKit)
import UIKit

struct UIKitScrollView<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let firstItemId: String?
    let itemCount: Int
    @Binding var scrollToBottom: Bool
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIKitScrollViewController<Content> {
        let vc = UIKitScrollViewController(content: content)
        vc.onNearTop = onNearTop
        vc.onAtBottomChanged = onAtBottomChanged
        return vc
    }

    func updateUIViewController(_ vc: UIKitScrollViewController<Content>, context: Context) {
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

final class UIKitScrollViewController<Content: View>: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.backgroundColor = .clear
        sv.keyboardDismissMode = .interactive
        sv.contentInsetAdjustmentBehavior = .automatic
        return sv
    }()

    var hostingController: UIHostingController<Content>!
    var lastFirstItemId: String?
    var lastItemCount: Int = 0
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?
    private var didInitialScroll = false
    private var contentSizeObservation: NSKeyValueObservation?
    private var hasTriggeredNearTop = false
    private var lastAtBottomState = true
    private var wasAtBottomBeforeKeyboard = true
    private var shouldScrollToBottomAfterLayout = false

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

        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] sv, _ in
            if let self = self, !self.didInitialScroll && sv.contentSize.height > sv.bounds.height {
                self.didInitialScroll = true
                self.scrollToBottom(animated: false)
            }
        }
    }

    private func setupKeyboardDismissGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToDismissKeyboard(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        hostingController.view.addGestureRecognizer(tapGesture)
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

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let screenHeight = UIScreen.main.bounds.height
        let isKeyboardHiding = endFrame.origin.y >= screenHeight

        // Only handle hide animation here
        guard isKeyboardHiding else { return }

        let animationCurve = UIView.AnimationOptions(rawValue: curveValue << 16)

        UIView.animate(withDuration: duration, delay: 0, options: [animationCurve, .beginFromCurrentState]) {
            // Force layout to animate with keyboard
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        wasAtBottomBeforeKeyboard = isAtBottom()

        guard wasAtBottomBeforeKeyboard,
              let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt,
              let window = view.window else { return }

        // Calculate the expected bottom inset after keyboard appears
        let scrollViewFrameInWindow = scrollView.convert(scrollView.bounds, to: window)
        let keyboardOverlap = max(0, scrollViewFrameInWindow.maxY - keyboardFrame.origin.y)

        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height
        let currentInset = scrollView.adjustedContentInset.bottom
        let expectedInset = currentInset + keyboardOverlap
        let maxOffsetY = max(0, contentHeight - frameHeight + expectedInset)

        let animationCurve = UIView.AnimationOptions(rawValue: curveValue << 16)

        UIView.animate(withDuration: duration, delay: 0, options: [animationCurve, .beginFromCurrentState]) {
            self.scrollView.contentOffset = CGPoint(x: 0, y: maxOffsetY)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard wasAtBottomBeforeKeyboard,
              let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let animationCurve = UIView.AnimationOptions(rawValue: curveValue << 16)

        // Delay slightly to let the system adjust insets first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self else { return }
            UIView.animate(withDuration: duration - 0.01, delay: 0, options: [animationCurve, .beginFromCurrentState]) {
                self.scrollToBottom(animated: false)
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if isAtBottom() {
            shouldScrollToBottomAfterLayout = true

            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.shouldScrollToBottomAfterLayout = false
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if shouldScrollToBottomAfterLayout {
            scrollToBottom(animated: false)
        }
    }

    private func isAtBottom() -> Bool {
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height
        let offsetY = scrollView.contentOffset.y
        let adjustedInset = scrollView.adjustedContentInset.bottom
        return (contentHeight - (offsetY + frameHeight - adjustedInset)) <= 100
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
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    func updateContent(_ content: Content) {
        hostingController.rootView = content
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
            scrollView.contentOffset.y = oldOffset + delta
        }
    }

    func scrollToBottom(animated: Bool) {
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height
        let bottomInset = scrollView.adjustedContentInset.bottom
        let maxOffsetY = max(0, contentHeight - frameHeight + bottomInset)
        scrollView.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: animated)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height
        let bottomInset = scrollView.adjustedContentInset.bottom

        // 1. Wrap Near Top detection in async to fix "Modifying state" error
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

        // 2. Wrap At Bottom detection in async as well
        // Account for bottom inset when calculating if at bottom
        let distanceFromBottom = contentHeight - (offsetY + frameHeight - bottomInset)
        let isAtBottom = distanceFromBottom <= 100
        if isAtBottom != lastAtBottomState {
            lastAtBottomState = isAtBottom
            DispatchQueue.main.async { [weak self] in
                self?.onAtBottomChanged?(isAtBottom)
            }
        }
    }
}

#elseif canImport(AppKit)
import AppKit

// MARK: - macOS Implementation using AppKit
struct UIKitScrollView<Content: View>: NSViewControllerRepresentable {
    let content: Content
    let firstItemId: String?
    let itemCount: Int
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
