import SwiftUI
import UniformTypeIdentifiers
struct UploadModalView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isHovering = false
    var onFileSelected: ((URL) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Transcribe audio and video")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            VStack(spacing: 20) {
                VStack(spacing: 15) {
                    Text("Drag & Drop")
                        .font(.headline)
                    
                    Image(systemName: "headphones")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    
                    Text("AAC, MP3, M4A, WAV, WMA\nMOV, MPEG, MP4, WMV")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Browse files") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [.audio, .audiovisualContent]
                        if panel.runModal() == .OK {
                            if let url = panel.url {
                                onFileSelected?(url)
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isHovering ? Color.blue.opacity(0.05) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundColor(isHovering ? .blue : .gray.opacity(0.3))
                )
                .padding()
                .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
                    if let provider = providers.first {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                DispatchQueue.main.async {
                                    onFileSelected?(url)
                                    dismiss()
                                }
                            } else if let url = item as? URL {
                                DispatchQueue.main.async {
                                    onFileSelected?(url)
                                    dismiss()
                                }
                            }
                        }
                        return true
                    }
                    return false
                }
            }
        }
        .frame(width: 500, height: 400)
        .background(Material.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
    }
}
