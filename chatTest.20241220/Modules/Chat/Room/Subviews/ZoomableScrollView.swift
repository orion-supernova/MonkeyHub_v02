import SwiftUI

#if canImport(UIKit)
import UIKit

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content
    private var onZoomScaleChanged: ((CGFloat) -> Void)?

    init(
        onZoomScaleChanged: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.onZoomScaleChanged = onZoomScaleChanged
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        // FIX: Wrapped content in AnyView to match the Coordinator's UIHostingController<AnyView>
        let hostingController = UIHostingController(rootView: AnyView(content.ignoresSafeArea()))
        hostingController.view.backgroundColor = .clear
        
        // Add the hosting controller's view to the scroll view
        let contentView = hostingController.view!
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.hostingController = hostingController
        context.coordinator.onZoomScaleChanged = onZoomScaleChanged

        // Double tap gesture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // FIX: Package update content into AnyView to correctly match the hostingController rootView type
        context.coordinator.hostingController?.rootView = AnyView(content.ignoresSafeArea())
        context.coordinator.onZoomScaleChanged = onZoomScaleChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>!
        var onZoomScaleChanged: ((CGFloat) -> Void)?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContentView(scrollView)
            onZoomScaleChanged?(scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            onZoomScaleChanged?(scale)
        }

        private func centerContentView(_ scrollView: UIScrollView) {
            guard let contentView = hostingController?.view else { return }
            
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            
            contentView.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: hostingController?.view)
                let zoomRect = calculateZoomRect(for: scrollView, at: point, with: 3.0)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        private func calculateZoomRect(for scrollView: UIScrollView, at point: CGPoint, with scale: CGFloat) -> CGRect {
            let size = CGSize(
                width: scrollView.frame.size.width / scale,
                height: scrollView.frame.size.height / scale
            )
            let origin = CGPoint(
                x: point.x - (size.width / 2.0),
                y: point.y - (size.height / 2.0)
            )
            return CGRect(origin: origin, size: size)
        }
    }
}
#else
struct ZoomableScrollView<Content: View>: View {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            content
        }
    }
}
#endif
