import SwiftUI

/// Heat map of time spent per grid cell. Drawn in the same coordinates as
/// `GridView`. Intensity uses a square-root scale so brief visits stay visible.
struct HeatmapLayer: View {
    let cells: [HeatCell]

    var body: some View {
        Canvas { gc, size in
            guard let maxSeconds = cells.map(\.seconds).max(), maxSeconds > 0 else { return }
            let span = GridView.highMidi - GridView.lowMidi
            let cellW = size.width * GridCellCount.resonanceBinWidth / 100
            let cellH = size.height / span
            for c in cells {
                let top = size.height * (1 - (Double(c.midi) + 0.5 - GridView.lowMidi) / span)
                guard top > -cellH, top < size.height else { continue }
                let strength = (c.seconds / maxSeconds).squareRoot()
                let rect = CGRect(x: Double(c.bin) * cellW, y: top, width: cellW, height: cellH)
                gc.fill(Path(rect), with: .color(Color.orange.opacity(0.2 + 0.7 * strength)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Session averages joined in time order; the newest is drawn larger.
struct HistoryTraceLayer: View {
    let points: [HistoryPoint]

    var body: some View {
        Canvas { gc, size in
            func pt(_ p: HistoryPoint) -> CGPoint {
                let t = (p.midi - GridView.lowMidi) / (GridView.highMidi - GridView.lowMidi)
                return CGPoint(x: size.width * min(1, max(0, p.score / 100)),
                               y: size.height * (1 - min(1, max(0, t))))
            }
            var path = Path()
            for (i, p) in points.enumerated() {
                if i == 0 { path.move(to: pt(p)) } else { path.addLine(to: pt(p)) }
            }
            gc.stroke(path, with: .color(.primary.opacity(0.7)),
                      style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (i, p) in points.enumerated() {
                let r: Double = i == points.count - 1 ? 6 : 4
                let c = pt(p)
                let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                gc.fill(dot, with: .color(Color(.systemBackground)))
                gc.stroke(dot, with: .color(.primary), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
