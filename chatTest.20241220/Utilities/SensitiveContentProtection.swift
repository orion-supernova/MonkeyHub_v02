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

    func makeUIViewController(context: Context) -> SecureContentHostingController<Content> {
        SecureContentHostingController(rootView: content)
    }

    func updateUIViewController(_ uiViewController: SecureContentHostingController<Content>, context: Context) {
        uiViewController.updateRootView(content)
    }
}

private final class SecureContentHostingController<Content: View>: UIViewController {
    private let secureTextField = UITextField()
    private let hostingController: UIHostingController<Content>

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
        setupSecureContainer()
    }

    func updateRootView(_ rootView: Content) {
        hostingController.rootView = rootView
    }

    private func setupSecureContainer() {
        view.backgroundColor = .clear

        secureTextField.translatesAutoresizingMaskIntoConstraints = false
        secureTextField.isSecureTextEntry = true
        secureTextField.backgroundColor = .clear
        secureTextField.borderStyle = .none
        secureTextField.textColor = .clear
        secureTextField.tintColor = .clear
        secureTextField.clipsToBounds = true
        secureTextField.isAccessibilityElement = false

        view.addSubview(secureTextField)
        NSLayoutConstraint.activate([
            secureTextField.topAnchor.constraint(equalTo: view.topAnchor),
            secureTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            secureTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            secureTextField.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let secureContainerView = secureTextField.subviews.first(where: {
            String(describing: type(of: $0)).contains("LayoutCanvasView")
        }) ?? secureTextField.subviews.first ?? secureTextField

        secureContainerView.backgroundColor = .clear

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        secureContainerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: secureContainerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: secureContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: secureContainerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: secureContainerView.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }
}
#endif
