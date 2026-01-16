import SwiftUI
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

final class UIKitScrollViewController<Content: View>: UIViewController, UIScrollViewDelegate {
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.backgroundColor = .clear
        sv.keyboardDismissMode = .interactive
        return sv
    }()

    var hostingController: UIHostingController<Content>! // internal access
    var lastFirstItemId: String?
    var lastItemCount: Int = 0
    var onNearTop: (() -> Void)?
    var onAtBottomChanged: ((Bool) -> Void)?
    private var didInitialScroll = false
    private var contentSizeObservation: NSKeyValueObservation?
    private var hasTriggeredNearTop = false // Ensure this is present
    private var lastAtBottomState = true

    init(content: Content) {
        super.init(nibName: nil, bundle: nil)
        self.hostingController = UIHostingController(rootView: content)
        self.hostingController.sizingOptions = [.intrinsicContentSize]
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        setupHostingController()
        
        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] sv, _ in
            if let self = self, !self.didInitialScroll && sv.contentSize.height > sv.bounds.height {
                self.didInitialScroll = true
                self.scrollToBottom(animated: false)
            }
        }
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
        let bottom = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: animated)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let frameHeight = scrollView.bounds.height

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
            let isAtBottom = (contentHeight - (offsetY + frameHeight)) <= 100
            if isAtBottom != lastAtBottomState {
                lastAtBottomState = isAtBottom
                DispatchQueue.main.async { [weak self] in
                    self?.onAtBottomChanged?(isAtBottom)
                }
            }
        }
}
