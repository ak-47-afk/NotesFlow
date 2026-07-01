import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    // We check keychain status dynamically when the view evaluates.
    var hasApiKeyInKeychain: Bool {
        guard let key = KeychainHelper.standard.readApiKey(), !key.isEmpty else { return false }
        return true
    }

    var body: some View {
        // Show main app only if BOTH: onboarding was completed AND a valid API key
        // exists in THIS device's Keychain.
        if hasCompletedOnboarding && hasApiKeyInKeychain {
            MainSplitView()
        } else {
            OnboardingView()
                .onAppear {
                    // Reset onboarding flag if key is missing — forces fresh setup
                    if !hasApiKeyInKeychain {
                        hasCompletedOnboarding = false
                    }
                }
        }
    }
}
