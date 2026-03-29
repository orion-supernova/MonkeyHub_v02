import SwiftUI
import Combine

struct SensitiveContentProtectionModifier: ViewModifier {
    let isEnabled: Bool

    #if canImport(UIKit)
    @State private var isLiveCaptureActive = UIScreen.main.isCaptured
    #endif

    func body(content: Content) -> some View {
        Group {
            if isEnabled {
                protectedContent(content)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private func protectedContent(_ content: Content) -> some View {
        #if canImport(UIKit)
        IOSSecureContentContainer(content: content)
            .overlay {
                if isLiveCaptureActive {
                    SensitiveContentShieldOverlay()
                }
            }
            .onAppear {
                isLiveCaptureActive = UIScreen.main.isCaptured
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                isLiveCaptureActive = UIScreen.main.isCaptured
            }
        #else
        content
        #endif
    }
}

extension View {
    func sensitiveContentProtection(enabled: Bool) -> some View {
        modifier(SensitiveContentProtectionModifier(isEnabled: enabled))
    }
}

private struct SensitiveContentShieldOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 28, weight: .semibold))
                Text("Protected Content Hidden")
                    .font(.headline)
                Text("Screen recording, mirroring, or broadcast is active.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Protected content hidden while screen capture is active.")
    }
}

#if canImport(UIKit)
import UIKit

private struct IOSSecureContentContainer<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> SecureLayerHostingController<Content> {
        SecureLayerHostingController(rootView: content)
    }

    func updateUIViewController(_ uiViewController: SecureLayerHostingController<Content>, context: Context) {
        uiViewController.updateRootView(content)
    }
}

private final class SecureLayerHostingController<Content: View>: UIViewController {
    private let secureTextField = UITextField()
    private let containerView = UIView()
    private let hostingController: UIHostingController<Content>
    private var didApplyProtection = false

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyProtectionIfNeeded()
        synchronizeProtectedLayerFrame()
    }

    func updateRootView(_ rootView: Content) {
        hostingController.rootView = rootView
        view.setNeedsLayout()
    }

    private func setupViews() {
        view.backgroundColor = .clear
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        view.addSubview(containerView)

        secureTextField.translatesAutoresizingMaskIntoConstraints = false
        secureTextField.isSecureTextEntry = true
        secureTextField.backgroundColor = .clear
        secureTextField.borderStyle = .none
        secureTextField.textColor = .clear
        secureTextField.tintColor = .clear
        secureTextField.isUserInteractionEnabled = false
        secureTextField.alpha = 0.01
        view.insertSubview(secureTextField, at: 0)

        NSLayoutConstraint.activate([
            secureTextField.topAnchor.constraint(equalTo: view.topAnchor),
            secureTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            secureTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            secureTextField.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    private func applyProtectionIfNeeded() {
        guard !didApplyProtection else { return }
        guard let secureSublayer = secureTextField.layer.sublayers?.first else { return }

        secureSublayer.addSublayer(containerView.layer)
        didApplyProtection = true
    }

    private func synchronizeProtectedLayerFrame() {
        guard didApplyProtection else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerView.layer.frame = secureTextField.bounds
        CATransaction.commit()
    }
}
#endif
