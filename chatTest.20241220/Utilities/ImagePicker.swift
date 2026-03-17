import PhotosUI
import SwiftUI

#if canImport(UIKit)
import Photos
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: PlatformImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        // Pass PHPhotoLibrary.shared() so we get assetIdentifiers,
        // which lets us use PHImageManager with networkAccessAllowed = true
        // to download photos that are in iCloud but not on device.
        var config = PHPickerConfiguration(photoLibrary: .shared())
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
            guard let result = results.first else { return }

            // Use PHAsset + PHImageManager so iCloud photos are downloaded automatically
            if let assetId = result.assetIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                guard let asset = fetchResult.firstObject else {
                    showError("Photo not found in library.")
                    return
                }

                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true   // download from iCloud if needed
                options.isSynchronous = false

                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        DispatchQueue.main.async { self.showError(error.localizedDescription) }
                        return
                    }
                    guard let data, let image = UIImage(data: data) else {
                        DispatchQueue.main.async { self.showError("Could not read photo data.") }
                        return
                    }
                    DispatchQueue.main.async { self.parent.image = image }
                }
            } else {
                // Fallback: no asset identifier (e.g. shared album), use item provider
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                    if let error {
                        DispatchQueue.main.async { self.showError(error.localizedDescription) }
                        return
                    }
                    guard let data, let image = UIImage(data: data) else {
                        DispatchQueue.main.async { self.showError("Could not read photo data.") }
                        return
                    }
                    DispatchQueue.main.async { self.parent.image = image }
                }
            }
        }

        private func showError(_ message: String) {
            AlertManager.shared.showAlert(title: "Photo Error", message: message)
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
