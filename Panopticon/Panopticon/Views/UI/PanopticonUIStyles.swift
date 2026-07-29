//
//  PanopticonUIStyles.swift
//  Panopticon
//
//  Reusable styling components for the new UI
//

import SwiftUI

extension View {
  /// Applies complete Panopticon style with rounded rectangle shape
  func panopticonStyle(
    cornerRadius: CGFloat = 735.4068,
    backgroundColor: Color = .white
  ) -> some View {
    self
      .background(backgroundColor)
      .cornerRadius(cornerRadius)
  }

  /// Applies complete Panopticon style with circle shape
  func panopticonCircleStyle(backgroundColor: Color = .white) -> some View {
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
    width: CGFloat = 31.40301,
    height: CGFloat = 30.4514,
    pressedScale: CGFloat = 0.97,
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
          .fill(Color.white)

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
    font: Font = .custom("InstrumentSerif-Regular", size: 18),
    foregroundColor: Color = Color(red: 0.2, green: 0.2, blue: 0.2),
    horizontalPadding: CGFloat = 11.77829,
    height: CGFloat = 30.4514,
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
