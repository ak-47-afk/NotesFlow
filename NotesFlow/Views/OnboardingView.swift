import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @State private var currentStep = 0
    @AppStorage("geminiAPIKey") private var apiKey: String = ""
    @State private var isKeyVisible = false
    
    // Services
    var aiservice = AIService()
    var transcriptionService = TranscriptionService()
    var whisperService = WhisperTranscriptionService()
    
    var body: some View {
        VStack(spacing: 0) {
            
            VStack {
                PagingIndicator(numberOfPages: 5, currentPage: currentStep)
                    .padding(.top, 30)
                
                Spacer()
                
                // Content area
                switch currentStep {
                case 0:
                    StepOneView(onContinue: { withAnimation { currentStep += 1 } })
                case 1:
                    StepTwoView(apiKey: $apiKey, isKeyVisible: $isKeyVisible, onBack: { withAnimation { currentStep -= 1 } }, onContinue: {
                        KeychainHelper.standard.saveApiKey(apiKey)
                        withAnimation { currentStep += 1 }
                    })
                case 2:
                    StepThreeView(transcriptionService: transcriptionService, onBack: { withAnimation { currentStep -= 1 } }, onContinue: { withAnimation { currentStep += 1 } })
                case 3:
                    StepFourView(whisperService: whisperService, onBack: { withAnimation { currentStep -= 1 } }, onContinue: { withAnimation { currentStep += 1 } })
                case 4:
                    StepFiveView(onBack: { withAnimation { currentStep -= 1 } }, onFinish: {
                        hasCompletedOnboarding = true
                    })
                default:
                    EmptyView()
                }
                
                Spacer()
            }
            .padding(.horizontal, 50)
            .padding(.bottom, 40)
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 550, height: 500)
    }
}

// MARK: - Step 1
struct StepOneView: View {
    var onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 10)
            
            Text("NotesFlow")
                .font(.system(size: 32, weight: .bold))
            
            Text("Local-first AI Notes")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            
            Text("Capture every meeting privately. Transcripts, summaries, and action items — all processed on your device.")
                .multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.8))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 40)
            
            HStack {
                Spacer()
                Button(action: onContinue) {
                    Text("Continue →")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

// MARK: - Step 2
struct StepTwoView: View {
    @Binding var apiKey: String
    @Binding var isKeyVisible: Bool
    var onBack: () -> Void
    var onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .modifier(CircularIconBackground(color: .blue))
                .padding(.bottom, 10)
            
            Text("AI Intelligence")
                .font(.system(size: 28, weight: .bold))
            
            Text("NotesFlow uses Google Gemini to generate structured summaries\nfrom your transcripts. Your API key is stored securely in your macOS\nKeychain.")
                .multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.8))
                .lineSpacing(4)
                .padding(.bottom, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("GEMINI KEY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.secondary)
                    
                    if isKeyVisible {
                        TextField("Alza...", text: $apiKey)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField("Alza...", text: $apiKey)
                            .textFieldStyle(.plain)
                    }
                    
                    Button(action: { isKeyVisible.toggle() }) {
                        Image(systemName: isKeyVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                
                HStack {
                    Link("Where do I find my API key?", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.caption)
                        .foregroundColor(.blue)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Local Keychain")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 20)
            
            HStack {
                Button(action: onBack) {
                    Text("Back")
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onContinue) {
                    Text("Continue →")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !apiKey.isEmpty))
                .disabled(apiKey.isEmpty)
            }
        }
    }
}

// MARK: - Step 3
struct StepThreeView: View {
    var transcriptionService: TranscriptionService
    var onBack: () -> Void
    var onContinue: () -> Void
    
    @StateObject private var permissions = PermissionsHelper()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("System Permissions")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 5)
            
            Text("NotesFlow needs access to capture both sides of your meetings.\nEverything is processed locally on your device.")
                .multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.8))
                .lineSpacing(4)
                .padding(.bottom, 10)
            
            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    iconBg: Color.blue.opacity(0.2),
                    iconColor: .blue,
                    title: "Microphone",
                    description: "Required to record audio for transcription.",
                    isGranted: permissions.microphoneGranted,
                    action: {
                        permissions.requestMicrophone()
                    }
                )
                
                PermissionRow(
                    icon: "display",
                    iconBg: Color.gray.opacity(0.2),
                    iconColor: .primary,
                    title: "Screen & System Audio",
                    description: "Required to automatically detect meetings from window titles.",
                    isGranted: permissions.screenRecordingGranted,
                    action: {
                        permissions.requestScreenRecording()
                    }
                )
                
                PermissionRow(
                    icon: "figure.roll",
                    iconBg: Color.gray.opacity(0.2),
                    iconColor: .primary,
                    title: "Accessibility",
                    description: "Required for native meeting detection if Screen Recording is denied.",
                    isGranted: permissions.accessibilityGranted,
                    action: {
                        permissions.openAccessibilitySettings()
                    }
                )
            }
            .padding(.bottom, 10)
            
            HStack {
                Button(action: onBack) {
                    Text("Back")
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onContinue) {
                    Text("Continue →")
                }
                .buttonStyle(PrimaryButtonStyle()) 
                // We can let them continue even without granting everything, 
                // because they can do it later in settings. 
                // Or require mic at least:
                .disabled(!permissions.microphoneGranted)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            permissions.checkPermissions()
        }
    }
}

struct PermissionRow: View {
    var icon: String
    var iconBg: Color
    var iconColor: Color
    var title: String
    var description: String
    var isGranted: Bool
    var action: () -> Void
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconBg)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Granted")
                }
                .foregroundColor(.blue)
                .font(.subheadline.bold())
            } else {
                Button(action: action) {
                    Text("Grant Access")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Step 4
struct StepFourView: View {
    var whisperService: WhisperTranscriptionService
    var onBack: () -> Void
    var onContinue: () -> Void
    
    @AppStorage("whisperModel") private var selectedModel: String = "base"
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .modifier(CircularIconBackground(color: .purple))
                .padding(.bottom, 10)
            
            Text("AI Transcription")
                .font(.system(size: 28, weight: .bold))
            
            Text("NotesFlow downloads an AI model to transcribe meetings locally.\nChoose your preferred balance of speed and accuracy.")
                .multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.8))
                .lineSpacing(4)
                .padding(.bottom, 10)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("MODEL QUALITY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Picker("", selection: $selectedModel) {
                    Text("Fast (Base Model ~140MB) - English only").tag("base")
                    Text("Accurate (Large Model ~1.5GB) - Multilingual / Hindi").tag("large-v3-v20240930_turbo")
                }
                .pickerStyle(RadioGroupPickerStyle())
                .disabled(whisperService.isDownloadingModel || whisperService.isModelLoaded)
                
                if whisperService.isDownloadingModel || whisperService.isModelLoaded {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        Text(whisperService.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.bottom, 10)
            
            HStack {
                Button(action: onBack) {
                    Text("Back")
                }
                .buttonStyle(.plain)
                .disabled(whisperService.isDownloadingModel)
                
                Spacer()
                
                if whisperService.isModelLoaded {
                    Button(action: onContinue) {
                        Text("Continue →")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(action: {
                        Task {
                            try? await whisperService.loadModels()
                            if whisperService.isModelLoaded {
                                onContinue()
                            }
                        }
                    }) {
                        if whisperService.isDownloadingModel {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 10)
                        } else {
                            Text("Download Model")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(whisperService.isDownloadingModel)
                }
            }
        }
    }
}

// MARK: - Step 5
struct StepFiveView: View {
    var onBack: () -> Void
    var onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark")
                .modifier(CircularIconBackground(color: .blue.opacity(0.2)))
                .padding(.bottom, 10)
                // Need a blue checkmark on light blue bg
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.blue)
                )
            
            Text("You're all set")
                .font(.system(size: 28, weight: .bold))
            
            Text("NotesFlow is ready to capture your meetings. We'll auto-\ndetect calls on Slack, Zoom, and Teams, or you can start a\nmanual recording any time.")
                .multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.8))
                .lineSpacing(4)
                .padding(.bottom, 40)
            
            HStack {
                Button(action: onBack) {
                    Text("Back")
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onFinish) {
                    Text("Open NotesFlow →")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
