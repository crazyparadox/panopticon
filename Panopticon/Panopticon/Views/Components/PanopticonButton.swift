//
//  PanopticonButton.swift
//  Panopticon
//
//  The primary call-to-action button, used by onboarding.
//
//  Restyled onto the reference design system: an accent (or surface) fill with
//  a layered hairline + drop shadow, and a short press scale. The previous
//  treatment leaned on hover lift, brightness shifts, and a blurred pulse —
//  all dropped, since this system expresses state through fill and elevation
//  rather than motion.
//

import AppKit
import SwiftUI

struct PanopticonButton: View {
  let title: String
  let action: () -> Void
  var width: CGFloat = 160
  var fontSize: CGFloat = 14
  /// Secondary treatment: surface fill with a hairline border and ink text.
  var isSubtle: Bool = false

  @State private var isPressed = false
  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var fill: Color {
    if isSubtle {
      return isHovered ? Theme.Palette.hover : Theme.Palette.surface
    }
    return isHovered ? Theme.Palette.accentInk : Theme.Palette.accent
  }

  private var foreground: Color {
    isSubtle ? Theme.Palette.ink : Theme.Palette.onAccent
  }

  private var stroke: Color {
    isSubtle ? Theme.Palette.line : Color.white.opacity(0.14)
  }

  var body: some View {
    Button(action: {
      withAnimation(Theme.Motion.feedback) { isPressed = true }

      NSHapticFeedbackManager.defaultPerformer.perform(
        .levelChange,
        performanceTime: .default
      )

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(Theme.Motion.control) { isPressed = false }
        action()
      }
    }) {
      Text(title)
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundColor(foreground)
        .frame(width: width, height: 40, alignment: .center)
        .background(
          RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(fill)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .strokeBorder(stroke, lineWidth: Theme.Metric.hairline)
        )
        .elevation(Theme.Shadow.button)
        .scaleEffect(reduceMotion || !isPressed ? 1 : Theme.Motion.pressedScale)
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .onHover { hovering in
      withAnimation(Theme.Motion.feedback) { isHovered = hovering }
    }
  }
}

struct PanopticonButton_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: 20) {
      PanopticonButton(title: "Start", action: {})
      PanopticonButton(title: "Continue", action: {}, width: 200)
      PanopticonButton(title: "Next", action: {}, width: 120, fontSize: 13)
      PanopticonButton(title: "Subtle", action: {}, isSubtle: true)
    }
    .padding(40)
    .background(Theme.Palette.canvas)
  }
}
