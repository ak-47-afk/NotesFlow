# NotesFlow

NotesFlow is a powerful, privacy-focused macOS application designed to automatically record, transcribe, and summarize your meetings and calls. It runs quietly in the background, capturing dual-channel audio (your microphone + system audio), transcribing it entirely on-device, and generating intelligent summaries.

## ✨ Features

- **Dual-Channel Audio Recording**: Seamlessly captures both your microphone input and system audio using Apple's ScreenCaptureKit.
- **On-Device Transcription**: Uses [WhisperKit](https://github.com/argmaxinc/WhisperKit) and CoreML to transcribe your meetings 100% locally on your Mac. No audio is ever uploaded to the cloud!
- **AI-Powered Summaries**: Generates structured, actionable insights from your transcripts using Google Gemini.
- **Native macOS Experience**: Built with SwiftUI, featuring a sleek menu bar item, a floating control window for easy access during calls, and secure Keychain storage for API keys.
- **Robust Storage Architecture**: Safely archives your recordings (`.m4a`), downloaded models, and meeting metadata using SwiftData and SQLite.

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later (for building from source)
- A Google Gemini API Key (for generating meeting summaries)

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/NotesFlow.git
   ```
2. Open `NotesFlow.xcodeproj` in Xcode.
3. Wait for Xcode to resolve the Swift Package Dependencies (`WhisperKit` and `swift-argument-parser`).
4. Build and Run the project (`Cmd + R`).

### Privacy & Permissions
On first launch, NotesFlow will request standard macOS permissions required to function:
- **Screen Recording**: To capture system audio (like voices from Zoom or Google Meet).
- **Microphone**: To capture your voice.
- **Accessibility**: (Optional) For global hotkey support.

## 🛠 Tech Stack

- **SwiftUI**: Modern, declarative UI framework.
- **ScreenCaptureKit & AVAudioEngine**: For high-performance audio routing and capture.
- **WhisperKit (CoreML)**: For on-device, privacy-preserving speech-to-text.
- **SwiftData**: For fast, native data persistence.
- **Google Gemini API**: For generating structural insights and summaries.

## 📂 File Architecture

Your data is safely stored in your local Documents folder under `~/Documents/NotesFlow/`.
- `Recordings/`: Where all your raw meeting `.m4a` audio files are saved.
- `Models/`: Where the Whisper CoreML models are cached.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page.

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.
