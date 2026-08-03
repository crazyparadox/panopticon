//
//  PanopticonMark.swift
//  Panopticon
//

import SwiftUI

/// The Panopticon mark, drawn rather than loaded: there is no logo image asset in
/// the bundle. Geometry matches the brand SVG's 100x99 space, so it stays in step
/// with the app icon and the website: a block with a rounded top, a bar under it,
/// then a gap and a half disc.
struct PanopticonMark: View {
  var size: CGFloat = 96
  var color: Color = Color(hex: "2645E3")

  var body: some View {
    Canvas { context, canvasSize in
      // Uniform scale from the 100x99 design space, centred.
      let scale = min(canvasSize.width / 100, canvasSize.height / 99)
      let dx = (canvasSize.width - 100 * scale) / 2
      let dy = (canvasSize.height - 99 * scale) / 2
      func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: dx + x * scale, y: dy + y * scale)
      }
      let shade = GraphicsContext.Shading.color(color)

      // Rounded-top block, y 0 to 23, corner radius 23.
      var top = Path()
      top.move(to: p(0, 23))
      top.addLine(to: p(0, 23))
      top.addArc(
        center: p(23, 23), radius: 23 * scale,
        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
      top.addLine(to: p(77, 0))
      top.addArc(
        center: p(77, 23), radius: 23 * scale,
        startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
      top.addLine(to: p(100, 23))
      top.closeSubpath()
      context.fill(top, with: shade)

      // Bar, y 23 to 46.
      context.fill(
        Path(CGRect(origin: p(0, 23), size: CGSize(width: 100 * scale, height: 23 * scale))),
        with: shade)

      // Half disc, flat top at y 49, radius 50.
      var bottom = Path()
      bottom.move(to: p(0, 49))
      bottom.addArc(
        center: p(50, 49), radius: 50 * scale,
        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
      bottom.closeSubpath()
      context.fill(bottom, with: shade)
    }
    .frame(width: size, height: size * 99 / 100)
    .accessibilityHidden(true)
  }
}
