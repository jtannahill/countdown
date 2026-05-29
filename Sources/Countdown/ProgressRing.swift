import SwiftUI

/// A small radial progress ring: faint full-circle track with a solid arc that
/// fills clockwise from 12 o'clock to `fraction` (0...1).
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
