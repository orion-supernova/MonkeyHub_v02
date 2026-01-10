import SwiftUI
import AVFoundation

#if canImport(UIKit)
struct CameraView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onMediaCaptured: (URL, Bool) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let mediaURL = info[.mediaURL] as? URL {
                let isVideo = info[.mediaType] as? String == "public.movie"
                parent.onMediaCaptured(mediaURL, isVideo)
            } else if let image = info[.originalImage] as? UIImage {
                if let data = image.jpegData(compressionQuality: 0.8) {
                    let filename = getDocumentsDirectory().appendingPathComponent("\(UUID().uuidString).jpg")
                    try? data.write(to: filename)
                    parent.onMediaCaptured(filename, false)
                }
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
        
        private func getDocumentsDirectory() -> URL {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return paths[0]
        }
    }
}
#else
struct CameraView: View {
    @Binding var isPresented: Bool
    var onMediaCaptured: (URL, Bool) -> Void

    var body: some View {
        VStack {
            Text("Camera is not available on native macOS.")
            Button("Close") { isPresented = false }
        }
        .padding()
    }
}
#endif
