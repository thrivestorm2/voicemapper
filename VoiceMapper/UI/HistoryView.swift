import SwiftUI

struct HistoryView: View {
    var body: some View {
        PlaceholderScreen(
            title: "History",
            systemImage: "chart.xyaxis.line",
            description: "Your progress, heat map, and past sessions will appear here."
        )
    }
}

#Preview {
    HistoryView()
}
