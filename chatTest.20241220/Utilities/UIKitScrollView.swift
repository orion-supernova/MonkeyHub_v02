import SwiftUI
import UIKit

/// A UIScrollView wrapper that preserves scroll position when content is prepended.
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
        // Check if content was prepended
        let wasPrepended = vc.lastFirstItemId != nil &&
                          firstItemId != nil &&
                          vc.lastFirstItemId != firstItemId &&
                          itemCount > vc.lastItemCount

        // Store state before update
        let previousContentHeight = vc.scrollView.contentSize.height
        let previousOffsetY = vc.scrollView.contentOffset.y

        // Update tracking BEFORE content update
        vc.lastFirstItemId = firstItemId
        vc.lastItemCount = itemCount

        if wasPrepended && previousContentHeight > 0 {
            // Prepending: update content and adjust offset synchronously
            vc.preservePositionDuringUpdate(content: content, previousHeight: previousContentHeight, previousOffset: previousOffsetY)
        } else {
            // Normal update
            vc.updateContent(content)
        }

        // Handle scroll to bottom
        if scrollToBottom {
            DispatchQueue.main.async {
                vc.scrollToBottom(animated: true)
                self.scrollToBottom = false
            }
        }

        // Update callbacks
        vc.onNearTop = onNearTop
        vc.onAtBottomChanged = onAtBottomChanged
    }
}

// MARK: - View Controller

final class UIKitScrollViewController<Content: View>: UIViewController, UIScrollViewDelegate {

    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.backgroundColor = .clear
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .interactive
        sv.contentInsetAdjustmentBehavior = .automatic
        return sv
    }()

    private var hostingController: UIHostingController<Content>!

    var lastFirstItemId: String?
    var lastItemCount: Int = 0
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?

    private var hasTriggeredNearTop = false
    private var lastAtBottomState = true
    private var didInitialScroll = false
    private var contentSizeObservation: NSKeyValueObservation?

    init(content: Content) {
        super.init(nibName: nil, bundle: nil)
        self.hostingController = UIHostingController(rootView: content)
        self.hostingController.sizingOptions = [.intrinsicContentSize]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupScrollView()
        setupHostingController()
        setupContentSizeObserver()
    }

    private func setupContentSizeObserver() {
        // Observe content size changes for initial scroll
        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, change in
            guard let self = self else { return }
            // Initial scroll to bottom when content becomes available
            if !self.didInitialScroll && scrollView.contentSize.height > scrollView.bounds.height {
                self.didInitialScroll = true
                DispatchQueue.main.async {
                    self.scrollToBottom(animated: false)
                }
            }
        }
    }

    deinit {
        contentSizeObservation?.invalidate()
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
        hostingController.safeAreaRegions = []

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
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
    }

    func preservePositionDuringUpdate(content: Content, previousHeight: CGFloat, previousOffset: CGFloat) {
        // Disable scrolling during update to prevent visual glitch
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update content
        hostingController.rootView = content
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()

        // Calculate and apply offset adjustment
        let newHeight = scrollView.contentSize.height
        let heightDelta = newHeight - previousHeight

        if heightDelta > 0 {
            scrollView.contentOffset.y = previousOffset + heightDelta
        }

        CATransaction.commit()
    }

    func scrollToBottom(animated: Bool) {
        let bottomOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: animated)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.bounds.height

        guard contentHeight > 0, frameHeight > 0 else { return }

        // Near top detection
        if offsetY <= 150 {
            if !hasTriggeredNearTop {
                hasTriggeredNearTop = true
                onNearTop?()
            }
        } else if offsetY > 200 {
            hasTriggeredNearTop = false
        }

        // At bottom detection
        let distanceFromBottom = contentHeight - (offsetY + frameHeight)
        let isAtBottom = distanceFromBottom <= 100

        if isAtBottom != lastAtBottomState {
            lastAtBottomState = isAtBottom
            DispatchQueue.main.async {
                self.onAtBottomChanged?(isAtBottom)
            }
        }
    }
}
