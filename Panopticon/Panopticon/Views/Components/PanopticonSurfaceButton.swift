//
//  PanopticonSurfaceButton.swift
//  Panopticon
//
//  Generic content button. Interaction model follows the reference design
//  system: a hairline-bordered surface, a hover fill, and a short press
//  scale. No hover lift, no brightness shifts — depth comes from the layered
//  hairline + drop shadow, not from motion.
//

import SwiftUI

struct PanopticonSurfaceButton<Content: View>: View {
  let action: () -> Void
  @ViewBuilder let content: () -> Content

  var background: Color = Theme.Palette.surface
  var foreground: Color = Theme.Palette.ink
  var borderColor: Color = Theme.Palette.line
  var cornerRadius: CGFloat = Theme.Radius.control
  var horizontalPadding: CGFloat = 12
  var verticalPadding: CGFloat = 7
  var minWidth: CGFloat? = nil
  var showShadow: Bool = true
  /// Filled treatment (accent or ink): the border becomes a subtle light
  /// inset so the fill reads as raised rather than flat.
  var isFilledStyle: Bool = false
  /// Outlined treatment: surface fill with an accent-weight border, for
  /// secondary actions that still need to draw the eye.
  var isOutlinedStyle: Bool = false

  @State private var isHovered = false
  @State private var isPressed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var resolvedBackground: Color {
    guard isHovered, !isFilledStyle else { return background }
    return Theme.Palette.hover
  }

  private var strokeColor: Color {
    if isFilledStyle { return Color.white.opacity(0.14) }
    if isOutlinedStyle { return Theme.Palette.accent }
    return borderColor
  }

  var body: some View {
    Button(action: {
      withAnimation(Theme.Motion.feedback) { isPressed = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        withAnimation(Theme.Motion.control) { isPressed = false }
        action()
      }
    }) {
      HStack(spacing: Theme.Metric.gap) {
        content()
          .foregroundColor(foreground)
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .frame(minWidth: minWidth)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(resolvedBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(strokeColor, lineWidth: isOutlinedStyle ? 1.5 : Theme.Metric.hairline)
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .elevation(showShadow ? Theme.Shadow.button : [])
      .scaleEffect(pressScale)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(Theme.Motion.feedback) { isHovered = hovering }
    }
    .pointingHandCursor()
  }

  private var pressScale: CGFloat {
    guard !reduceMotion, isPressed else { return 1 }
    return Theme.Motion.pressedScale
  }
}
