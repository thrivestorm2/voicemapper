import SwiftUI

struct RangeTableView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Range",
            systemImage: "music.note.list",
            description: "The colour-coded vocal range table will appear here."
        )
    }
}

#Preview {
    RangeTableView()
}
