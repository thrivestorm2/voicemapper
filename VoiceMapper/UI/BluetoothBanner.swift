import SwiftUI

/// "Wired headphones recommended" banner shown on Live while hearing yourself
/// over Bluetooth. See docs/PLAN.md §1a and docs/WIREFRAMES.md §2.
struct BluetoothBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Wired headphones recommended: Bluetooth adds ~150–250 ms delay.")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    BluetoothBanner {}
        .padding()
}
