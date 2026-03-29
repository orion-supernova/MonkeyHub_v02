import SwiftUI
import Combine

struct SensitiveContentProtectionModifier: ViewModifier {
    let isEnabled: Bool
    
    #if canImport(UIKit)
    @State private var isLiveCaptureActive = UIScreen.main.isCaptured
    #endif
    
    func body(content: Content) -> some View {
        #if canImport(UIKit)
        if isEnabled {
            ZStack {
                // The Secure Container
                IOSSecureContentContainer {
                    content
                }
                .ignoresSafeArea() // Fixes the black bars at top/bottom

                // The Overlay
                if isLiveCaptureActive {
                    SensitiveContentShieldOverlay()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                isLiveCaptureActive = UIScreen.main.isCaptured
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                isLiveCaptureActive = UIScreen.main.isCaptured
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func sensitiveContentProtection(enabled: Bool = true) -> some View {
        modifier(SensitiveContentProtectionModifier(isEnabled: enabled))
    }
}

// MARK: - Overlay View
private struct SensitiveContentShieldOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 32, weight: .semibold))
                Text("Protected Content")
                    .font(.headline)
                Text("Screen recording or mirroring is active.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
        // Allows user to still interact with the app if they really want to,
        // or set to true to block everything during recording.
        .allowsHitTesting(true)
    }
}

// MARK: - UIKit Implementation
#if canImport(UIKit)
import UIKit

private struct IOSSecureContentContainer<Content: View>: UIViewControllerRepresentable {
    let content: () -> Content

    func makeUIViewController(context: Context) -> SecureLayerViewController<Content> {
        SecureLayerViewController(rootView: content())
    }

    func updateUIViewController(_ uiViewController: SecureLayerViewController<Content>, context: Context) {
        uiViewController.update(content())
    }
}

private final class SecureLayerViewController<Content: View>: UIViewController {
    private let textField = UITextField()
    private let hostingController: UIHostingController<Content>
    
    // This is the container that will hold the layer
    private let containerView = UIView()

    init(rootView: Content) {
        self.hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        setupSecureTextField()
        setupHostingView()
    }
    
    private func setupSecureTextField() {
        textField.isSecureTextEntry = true
        textField.isUserInteractionEnabled = false
        view.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: view.topAnchor),
            textField.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Find the "Canvas" view inside the text field
        if let canvas = textField.subviews.first(where: { type(of: $0).description().contains("Canvas") }) {
            canvas.addSubview(containerView)
            containerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: canvas.topAnchor),
                containerView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
                containerView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor)
            ])
        }
    }
    
    private func setupHostingView() {
        addChild(hostingController)
        view.addSubview(hostingController.view) // Keep in main hierarchy for TOUCHES
        hostingController.didMove(toParent: self)
        
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // THE TRICK: Move the LAYER to the secure container,
        // but keep the VIEW in the main hierarchy.
        DispatchQueue.main.async {
            self.containerView.layer.addSublayer(self.hostingController.view.layer)
        }
    }

    func update(_ rootView: Content) {
        hostingController.rootView = rootView
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Ensure the layer follows the bounds of the screen/view
        hostingController.view.layer.frame = view.bounds
    }
}
#endif
