import SwiftUI

@main
struct VoiceMapperApp: App {
    @State private var audio = AudioEngine()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(audio)
        }
    }
}
