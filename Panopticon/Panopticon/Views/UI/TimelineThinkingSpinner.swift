//
//  TimelineThinkingSpinner.swift
//  Panopticon
//
//  Pixel-grid loader for long-running work, ported from the reference design
//  system's LoadingState (Drive variant): a 3×3 grid of square cells with a
//  chevron wavefront driving right. The 650ms cycle is shorter than the
//  sweep, so two fronts are always in flight. Reduced motion freezes the
//  grid at its dim state.
//

import SwiftUI

struct PixelGridLoader: View {
  /// Cell color. Status pills draw on dark fills, so they pass white.
  var tint: Color = Theme.Palette.ink
  var cellSize: CGFloat = 4
  var gap: CGFloat = 1.5

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animating = false

  /// Chevron wavefront: delay = (column + |row − 1|) × 90ms.
  private func delay(row: Int, column: Int) -> Double {
    Double(column + abs(row - 1)) * 0.09
  }

  var body: some View {
    VStack(spacing: gap) {
      ForEach(0..<3, id: \.self) { row in
        HStack(spacing: gap) {
          ForEach(0..<3, id: \.self) { column in
            RoundedRectangle(cornerRadius: 1, style: .continuous)
              .fill(tint)
              .frame(width: cellSize, height: cellSize)
              .opacity(animating && !reduceMotion ? 1.0 : 0.15)
              .animation(
                reduceMotion
                  ? nil
                  : .easeInOut(duration: 0.325)
                    .repeatForever(autoreverses: true)
                    .delay(delay(row: row, column: column)),
                value: animating
              )
          }
        }
      }
    }
    .onAppear { animating = true }
    .onDisappear { animating = false }
    .accessibilityHidden(true)
  }
}

/// Loader + shimmering label + live elapsed timer, for standalone contexts.
struct PixelGridLoadingState: View {
  var label: String = "Working"
  var tint: Color = Theme.Palette.ink

  @State private var startedAt = Date()

  var body: some View {
    HStack(spacing: 10) {
      PixelGridLoader(tint: tint)

      Text(label)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(Theme.Palette.ink3)

      TimelineView(.periodic(from: .now, by: 0.1)) { context in
        Text(elapsedText(now: context.date))
          .font(Theme.Font_.tabular(12))
          .foregroundColor(Theme.Palette.ink3)
      }
    }
  }

  private func elapsedText(now: Date) -> String {
    let total = max(0, now.timeIntervalSince(startedAt))
    if total < 60 { return String(format: "%.1fs", total) }
    return String(format: "%dm %.1fs", Int(total / 60), total.truncatingRemainder(dividingBy: 60))
  }
}
