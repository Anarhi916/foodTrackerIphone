import SwiftUI
import AVFoundation

struct PhotoCaptureScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var capturedImage: UIImage?

    var body: some View {
        VStack(spacing: 20) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)

                Button(action: analyzePhoto) {
                    Text("Анализировать")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)

                if viewModel.isLoading {
                    ProgressView("Распознавание...")
                }
            } else {
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("Сфотографируйте еду")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack(spacing: 16) {
                Button(action: { showCamera = true }) {
                    Label("Камера", systemImage: "camera")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }

                Button(action: { showLibrary = true }) {
                    Label("Галерея", systemImage: "photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .navigationTitle("Фото еды")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $capturedImage, sourceType: .camera)
        }
        .sheet(isPresented: $showLibrary) {
            ImagePicker(image: $capturedImage, sourceType: .photoLibrary)
        }
        .onChange(of: viewModel.showPhotoEditDialog) { _, newVal in
            if newVal { dismiss() }
        }
    }

    private func analyzePhoto() {
        guard let image = capturedImage,
              let data = image.jpegData(compressionQuality: 0.8) else { return }
        viewModel.analyzePhoto(data)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .camera
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if sourceType == .camera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
