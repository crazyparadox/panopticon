//
//  OnboardingWelcomeStepView.swift
//  Panopticon
//
//  First screen of setup, shown once the opening film has faded. Says what the
//  app is and what it will ask for, then hands over to the agent picker.
//

import SwiftUI

struct OnboardingWelcomeStepView: View {
  let onStart: () -> Void

  @State private var titleOpacity: Double = 0
  @State private var titleLift: CGFloat = 14
  @State private var pointsOpacity: Double = 0
  @State private var buttonOpacity: Double = 0

  private let points: [(icon: String, title: String, body: String)] = [
    (
      "record.circle",
      "It records your screen",
      "Periodic captures, stored in a database on this Mac. Idle stretches and apps you block are skipped."
    ),
    (
      "square.stack.3d.up",
      "It builds a timeline",
      "An AI model you choose turns those captures into a readable account of the day."
    ),
    (
      "point.3.filled.connected.trianglepath.dotted",
      "Your agents can read it",
      "Served over MCP from a server you host, so the only thing holding your day is infrastructure you own."
    ),
  ]

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)

      VStack(spacing: 10) {
        Text("Welcome to Panopticon")
          .font(.system(size: 34, weight: .semibold))
          .foregroundColor(Theme.Palette.ink)
          .tracking(-0.4)
        Text("A memory of your screen, kept on hardware you own.")
          .font(.system(size: 15))
          .foregroundColor(Theme.Palette.ink2)
      }
      .multilineTextAlignment(.center)
      .offset(y: titleLift)
      .opacity(titleOpacity)

      VStack(alignment: .leading, spacing: 18) {
        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
          HStack(alignment: .top, spacing: 13) {
            Image(systemName: point.icon)
              .font(.system(size: 15, weight: .medium))
              .foregroundColor(Theme.Palette.accent)
              .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
              Text(point.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Palette.ink)
              Text(point.body)
                .font(.system(size: 13))
                .foregroundColor(Theme.Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      .frame(maxWidth: 430, alignment: .leading)
      .padding(.top, 34)
      .opacity(pointsOpacity)

      PanopticonSurfaceButton(
        action: onStart,
        content: { Text("Get started").font(.system(size: 15)).fontWeight(.semibold) },
        background: Theme.Palette.accent,
        foreground: Theme.Palette.onAccent,
        borderColor: .clear,
        cornerRadius: Theme.Radius.control,
        horizontalPadding: 26,
        verticalPadding: 12,
        minWidth: 170,
        isFilledStyle: true
      )
      .padding(.top, 34)
      .opacity(buttonOpacity)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
    .task { await reveal() }
  }

  /// Staggered so the eye lands on the title first; the film has just faded, so
  /// everything arriving at once would read as a jump cut.
  private func reveal() async {
    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)) {
      titleOpacity = 1
      titleLift = 0
    }
    try? await Task.sleep(nanoseconds: 240_000_000)
    withAnimation(.easeOut(duration: 0.55)) { pointsOpacity = 1 }
    try? await Task.sleep(nanoseconds: 260_000_000)
    withAnimation(.easeOut(duration: 0.45)) { buttonOpacity = 1 }
  }
}
