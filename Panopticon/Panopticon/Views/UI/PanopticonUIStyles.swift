//
//  PanopticonUIStyles.swift
//  Panopticon
//
//  Reusable styling components for the new UI
//

import SwiftUI

extension View {
  /// Surface fill with the standard control radius.
  ///
  /// This used to default to a 735pt radius (an effectively fully-round pill).
  /// The reference system uses square-ish 8pt controls, so that is the default
  /// now; pass an explicit radius where a pill is actually wanted.
  func panopticonStyle(
    cornerRadius: CGFloat = Theme.Radius.control,
    backgroundColor: Color = Theme.Palette.surface
  ) -> some View {
    self
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(backgroundColor)
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  /// Surface fill clipped to a circle.
  func panopticonCircleStyle(backgroundColor: Color = Theme.Palette.surface) -> some View {
    self
      .background(backgroundColor)
      .clipShape(Circle())
  }
}

struct PanopticonCircleButton<Content: View>: View {
  let action: () -> Void
  let size: CGSize
  let pressedScale: CGFloat
  let pressAnimation: Animation
  @ViewBuilder let content: () -> Content

  init(
    width: CGFloat = Theme.Metric.control,
    height: CGFloat = Theme.Metric.control,
    pressedScale: CGFloat = Theme.Motion.pressedScale,
    pressAnimation: Animation = .spring(response: 0.24, dampingFraction: 0.82),
    action: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.size = CGSize(width: width, height: height)
    self.pressedScale = pressedScale
    self.pressAnimation = pressAnimation
    self.action = action
    self.content = content
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .fill(Theme.Palette.surface)

        content()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(width: size.width, height: size.height)
      .contentShape(Circle())
    }
    .buttonStyle(
      PanopticonPressScaleButtonStyle(pressedScale: pressedScale, animation: pressAnimation)
    )
    .contentShape(Circle())
    .hoverScaleEffect(scale: 1.02)
    .pointingHandCursorOnHover(reassertOnPressEnd: true)
  }
}

struct PanopticonPillButton: View {
  let text: String
  let font: Font
  let foregroundColor: Color
  let horizontalPadding: CGFloat
  let height: CGFloat
  let fixedWidth: CGFloat?

  init(
    text: String,
    font: Font = Theme.Font_.label,
    foregroundColor: Color = Theme.Palette.ink,
    horizontalPadding: CGFloat = 12,
    height: CGFloat = Theme.Metric.control,
    fixedWidth: CGFloat? = nil
  ) {
    self.text = text
    self.font = font
    self.foregroundColor = foregroundColor
    self.horizontalPadding = horizontalPadding
    self.height = height
    self.fixedWidth = fixedWidth
  }

  var body: some View {
    Text(text)
      .font(font)
      .foregroundColor(foregroundColor)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .if(fixedWidth != nil) { view in
        view.frame(width: fixedWidth!, height: height)
      }
      .if(fixedWidth == nil) { view in
        view.padding(.horizontal, horizontalPadding)
          .frame(height: height)
      }
      .panopticonStyle()
  }
}
