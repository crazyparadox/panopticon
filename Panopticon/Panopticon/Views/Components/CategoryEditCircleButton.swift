import SwiftUI

struct CategoryEditCircleButton: View {
  let action: () -> Void
  var diameter: CGFloat = 30
  var iconSize: CGFloat? = nil
  var accessibilityLabel: String = "Edit categories"

  var body: some View {
    let resolvedIconSize = iconSize ?? diameter * 0.48

    Button(action: action) {
      Image("CategoryEditButton")
        .resizable()
        .scaledToFit()
        .frame(width: resolvedIconSize, height: resolvedIconSize)
        .frame(width: diameter, height: diameter)
        .background(Theme.Palette.accentTint)
        .clipShape(Circle())
        .overlay(
          Circle()
            .stroke(Theme.Palette.line, lineWidth: 1)
        )
    }
    .buttonStyle(PanopticonPressScaleButtonStyle(pressedScale: 0.97))
    .hoverScaleEffect(scale: 1.02)
    .pointingHandCursorOnHover(reassertOnPressEnd: true)
    .accessibilityLabel(accessibilityLabel)
  }
}
