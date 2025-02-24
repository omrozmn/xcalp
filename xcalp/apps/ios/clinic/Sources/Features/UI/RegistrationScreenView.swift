import SwiftUI

struct RegistrationScreenView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var photo: UIImage? = nil
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage? = nil
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Patient Details")) {
                        TextField("Name", text: $name)
                        TextField("Email", text: $email)
                        TextField("Phone", text: $phone)
                    }
                    
                    Section(header: Text("Photo")) {
                        if let photo = photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                                .shadow(radius: 10)
                        } else {
                            Button("Upload Photo") {
                                self.showingImagePicker = true
                            }
                        }
                    }
                }
                
                Button(action: {
                    // Save action
                }) {
                    Text("Save")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .padding()
                }
            }
            .navigationBarTitle("Register Patient", displayMode: .inline)
            .sheet(isPresented: $showingImagePicker, onDismiss: loadImage) {
                ImagePicker(image: self.$inputImage)
            }
        }
    }
    
    func loadImage() {
        guard let inputImage = inputImage else { return }
        photo = inputImage
    }
}

struct RegistrationScreenView_Previews: PreviewProvider {
    static var previews: some View {
        RegistrationScreenView()
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {}
}
