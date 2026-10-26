import SwiftUI

struct LiveView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Live",
            systemImage: "waveform",
            description: "Your pitch and resonance grid will appear here."
        )
    }
}

#Preview {
    LiveView()
}
