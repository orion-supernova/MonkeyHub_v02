import PhotosUI
import SwiftUI

#if canImport(UIKit)
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: PlatformImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}
#else
struct ImagePicker: View {
    @Binding var image: PlatformImage?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Text("Select an image")
            Button("Choose Image...") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.allowedContentTypes = [.image]
                
                if panel.runModal() == .OK {
                    if let url = panel.url, let image = NSImage(contentsOf: url) {
                        self.image = image
                    }
                }
                presentationMode.wrappedValue.dismiss()
            }
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
        }
        .frame(width: 300, height: 200)
        .padding()
    }
}
#endif
