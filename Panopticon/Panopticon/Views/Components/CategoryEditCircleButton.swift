import SwiftUI

struct CategoryEditCircleButton: View {
  let action: () -> Void
  var diameter: CGFloat = 30
  var iconSize: CGFloat? = nil
  var accessibilityLabel: String = "Edit categories"

  var body: some View {
    let resolvedIconSize = iconSize ?? diameter * 0.48

    Button(action: action) {
      Image(systemName: "pencil")
        .font(.system(size: resolvedIconSize * 0.75, weight: .medium))
        .foregroundColor(Theme.Palette.ink2)
        .frame(width: diameter, height: diameter)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.Palette.inset)
        )
    }
    .buttonStyle(PanopticonPressScaleButtonStyle(pressedScale: 0.97))
    .hoverScaleEffect(scale: 1.02)
    .pointingHandCursorOnHover(reassertOnPressEnd: true)
    .accessibilityLabel(accessibilityLabel)
  }
}
