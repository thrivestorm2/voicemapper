import SwiftUI

/// Temporary screen body used until each tab is built in its session.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
            .navigationTitle(title)
        }
    }
}
