import SwiftUI
import AVFoundation
import UIKit

struct CameraEditorView: View {
    @Binding var isPresented: Bool
    var onImageCaptured: (UIImage) -> Void

    @StateObject private var cameraManager = CameraManager()
    @State private var capturedImage: UIImage?
    @State private var drawingPaths: [DrawingPath] = []
    @State private var currentPath: DrawingPath?
    @State private var selectedColor: Color = .red
    @State private var isMirrored = false
    @State private var canvasSize: CGSize = .zero

    let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .white, .black]

    var body: some View {
        if let image = capturedImage {
            imageEditorView(image)
        } else {
            cameraPreviewView
        }
    }

    // MARK: - Camera Preview

    private var cameraPreviewView: some View {
        ZStack {
            CameraPreview(session: cameraManager.session, isMirrored: $isMirrored)
                .ignoresSafeArea()

            VStack {
                // Top controls
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                    Spacer()
                    if cameraManager.isFrontCamera {
                        Button(action: { isMirrored.toggle() }) {
                            Image(systemName: isMirrored ? "arrow.left.and.right.circle.fill" : "arrow.left.and.right.circle")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                                .shadow(radius: 3)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer()

                // Bottom controls
                HStack(spacing: 40) {
                    Button(action: { cameraManager.switchCamera() }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }

                    Button(action: {
                        cameraManager.capturePhoto { image in
                            let finalImage = cameraManager.isFrontCamera ? image.flipped() : image
                            capturedImage = finalImage
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        }
                    }

                    // Spacer to balance the layout since the flip button is on the left
                    Color.clear.frame(width: 50, height: 50)
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear { cameraManager.checkPermissions() }
    }

    // MARK: - Image Editor

    @ViewBuilder
    private func imageEditorView(_ image: UIImage) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: {
                        capturedImage = nil
                        drawingPaths = []
                        currentPath = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // Canvas area
                DrawingCanvasView(
                    image: image,
                    drawingPaths: $drawingPaths,
                    currentPath: $currentPath,
                    selectedColor: selectedColor,
                    canvasSize: $canvasSize
                )
                .clipped()

                // Tools section
                VStack(spacing: 0) {
                    // Color palette and Undo
                    HStack(spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(colors, id: \.self) { color in
                                    Circle()
                                        .fill(color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle().strokeBorder(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                                        )
                                        .onTapGesture { selectedColor = color }
                                }
                            }
                        }

                        Button(action: {
                            if !drawingPaths.isEmpty {
                                drawingPaths.removeLast()
                            }
                        }) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(drawingPaths.isEmpty ? Color.gray.opacity(0.5) : .white)
                        }
                        .disabled(drawingPaths.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    // Action buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            capturedImage = nil
                            drawingPaths = []
                            currentPath = nil
                        }) {
                            Text("Retake")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(12)
                        }

                        Button(action: {
                            let finalImage = renderImageWithDrawings(image: image)
                            onImageCaptured(finalImage)
                            isPresented = false
                        }) {
                            Text("Use Photo")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .background(Color.black.opacity(0.95))
            }
        }
    }

    // MARK: - Render Final Image

    private func renderImageWithDrawings(image: UIImage) -> UIImage {
        guard !drawingPaths.isEmpty, canvasSize != .zero else { return image }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(at: .zero)

            let ctx = context.cgContext
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Transform each path from canvas coordinates to image coordinates
            for path in drawingPaths {
                let transformedPath = transformToImageCoordinates(path: path, canvasSize: canvasSize, image: image)

                ctx.setStrokeColor(UIColor(transformedPath.color).cgColor)
                ctx.setLineWidth(transformedPath.lineWidth)

                ctx.beginPath()
                for (index, point) in transformedPath.points.enumerated() {
                    if index == 0 {
                        ctx.move(to: point)
                    } else {
                        ctx.addLine(to: point)
                    }
                }
                ctx.strokePath()
            }
        }
    }

    // Transform canvas coordinates to image coordinates
    private func transformToImageCoordinates(path: DrawingPath, canvasSize: CGSize, image: UIImage) -> DrawingPath {
        let imageAspect = image.size.width / image.size.height
        let canvasAspect = canvasSize.width / canvasSize.height

        var imageFrame: CGRect
        if imageAspect > canvasAspect {
            // Image is wider - fit to width, letterbox top/bottom
            let displayHeight = canvasSize.width / imageAspect
            let yOffset = (canvasSize.height - displayHeight) / 2
            imageFrame = CGRect(x: 0, y: yOffset, width: canvasSize.width, height: displayHeight)
        } else {
            // Image is taller - fit to height, pillarbox left/right
            let displayWidth = canvasSize.height * imageAspect
            let xOffset = (canvasSize.width - displayWidth) / 2
            imageFrame = CGRect(x: xOffset, y: 0, width: displayWidth, height: canvasSize.height)
        }

        let transformedPoints = path.points.map { point -> CGPoint in
            let relativeX = (point.x - imageFrame.minX) / imageFrame.width
            let relativeY = (point.y - imageFrame.minY) / imageFrame.height
            return CGPoint(
                x: relativeX * image.size.width,
                y: relativeY * image.size.height
            )
        }

        return DrawingPath(
            color: path.color,
            lineWidth: path.lineWidth * (image.size.width / imageFrame.width),
            points: transformedPoints
        )
    }
}

// MARK: - Drawing Canvas

struct DrawingCanvasView: View {
    let image: UIImage
    @Binding var drawingPaths: [DrawingPath]
    @Binding var currentPath: DrawingPath?
    let selectedColor: Color
    @Binding var canvasSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                // Drawing overlay
                Canvas { context, size in
                    // Draw all completed paths
                    for path in drawingPaths {
                        drawPath(path, in: context)
                    }

                    // Draw current path being drawn
                    if let current = currentPath {
                        drawPath(current, in: context)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChange(value.location, in: geometry.size)
                        }
                        .onEnded { _ in
                            handleDragEnd(in: geometry.size)
                        }
                )
            }
            .onAppear {
                canvasSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                canvasSize = newSize
            }
        }
    }

    private func drawPath(_ path: DrawingPath, in context: GraphicsContext) {
        var swiftUIPath = Path()
        for (index, point) in path.points.enumerated() {
            if index == 0 {
                swiftUIPath.move(to: point)
            } else {
                swiftUIPath.addLine(to: point)
            }
        }
        context.stroke(
            swiftUIPath,
            with: .color(path.color),
            style: StrokeStyle(lineWidth: path.lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func handleDragChange(_ location: CGPoint, in canvasSize: CGSize) {
        if currentPath == nil {
            currentPath = DrawingPath(color: selectedColor, lineWidth: 5, points: [location])
        } else {
            currentPath?.points.append(location)
        }
    }

    private func handleDragEnd(in canvasSize: CGSize) {
        guard let path = currentPath else { return }

        // CRITICAL FIX: Store canvas coordinates for display
        // We'll transform to image coordinates only when rendering final image
        drawingPaths.append(path)
        currentPath = nil
    }

    // Helper to transform canvas coordinates to image coordinates
    func transformToImageCoordinates(path: DrawingPath, canvasSize: CGSize) -> DrawingPath {
        let imageAspect = image.size.width / image.size.height
        let canvasAspect = canvasSize.width / canvasSize.height

        var imageFrame: CGRect
        if imageAspect > canvasAspect {
            let displayHeight = canvasSize.width / imageAspect
            let yOffset = (canvasSize.height - displayHeight) / 2
            imageFrame = CGRect(x: 0, y: yOffset, width: canvasSize.width, height: displayHeight)
        } else {
            let displayWidth = canvasSize.height * imageAspect
            let xOffset = (canvasSize.width - displayWidth) / 2
            imageFrame = CGRect(x: xOffset, y: 0, width: displayWidth, height: canvasSize.height)
        }

        let transformedPoints = path.points.map { point -> CGPoint in
            let relativeX = (point.x - imageFrame.minX) / imageFrame.width
            let relativeY = (point.y - imageFrame.minY) / imageFrame.height
            return CGPoint(
                x: relativeX * image.size.width,
                y: relativeY * image.size.height
            )
        }

        return DrawingPath(
            color: path.color,
            lineWidth: path.lineWidth * 3,
            points: transformedPoints
        )
    }
}

// MARK: - Models

struct DrawingPath {
    let color: Color
    let lineWidth: CGFloat
    var points: [CGPoint]
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var isMirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        context.coordinator.previewLayer = view.videoPreviewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            previewLayer.transform = isMirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var isFrontCamera = false

    private var photoOutput = AVCapturePhotoOutput()
    private var photoCompletionHandler: ((UIImage) -> Void)?

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.setupCamera() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupCamera() }
                }
            }
        default:
            break
        }
    }

    private func setupCamera(useFrontCamera: Bool = false) {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
                DispatchQueue.main.async { self?.configureSession(useFrontCamera: useFrontCamera) }
            }
        } else {
            configureSession(useFrontCamera: useFrontCamera)
        }
    }

    private func configureSession(useFrontCamera: Bool) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        isFrontCamera = useFrontCamera

        photoOutput.isHighResolutionCaptureEnabled = true
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func switchCamera() {
        setupCamera(useFrontCamera: !isFrontCamera)
    }

    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        photoCompletionHandler = completion
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.photoCompletionHandler?(image)
        }
    }
}

// MARK: - Extensions

extension UIImage {
    func flipped() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        let context = UIGraphicsGetCurrentContext()!
        context.translateBy(x: size.width, y: 0)
        context.scaleBy(x: -1.0, y: 1.0)
        draw(in: CGRect(origin: .zero, size: size))
        let flippedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return flippedImage ?? self
    }
}
