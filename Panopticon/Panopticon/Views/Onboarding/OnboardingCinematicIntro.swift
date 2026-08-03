//
//  OnboardingCinematicIntro.swift
//  Panopticon
//
//  Opening beat before the setup steps. The screen goes almost black, the mark
//  rises from the bottom, lands with a haptic tap and a low note, and the intro
//  card settles in after it.
//
//  Deliberately skippable and it only ever plays once: a first-run flourish that
//  you cannot get past is an obstacle, not an experience.
//

import AppKit
import SwiftUI

struct OnboardingCinematicIntro: View {
  let onBegin: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum Phase {
    case dark  // empty black, a beat of nothing
    case rising  // the mark travels up from below the fold
    case card  // intro copy settles in
  }

  @State private var phase: Phase = .dark
  @State private var markOffset: CGFloat = 190
  @State private var markOpacity: Double = 0
  @State private var markBlur: CGFloat = 10
  @State private var markScale: CGFloat = 0.94
  @State private var glowOpacity: Double = 0
  @State private var cardOffset: CGFloat = 26
  @State private var cardOpacity: Double = 0
  @State private var didPlay = false
  @State private var keyMonitor: Any?

  var body: some View {
    ZStack {
      // 90% black over whatever the window is showing, so the desktop is still
      // faintly there rather than replaced.
      Color.black.opacity(0.9).ignoresSafeArea()

      // Pool of light the mark rises into. Sits behind it and fades up with it.
      RadialGradient(
        colors: [Theme.Palette.accent.opacity(0.22), .clear],
        center: .center, startRadius: 0, endRadius: 340
      )
      .opacity(glowOpacity)
      .ignoresSafeArea()
      .allowsHitTesting(false)

      VStack(spacing: 0) {
        Spacer(minLength: 0)

        PanopticonMark(size: 96)
          .scaleEffect(markScale)
          .blur(radius: markBlur)
          .opacity(markOpacity)
          .offset(y: markOffset)

        if phase == .card {
          introCard
            .offset(y: cardOffset)
            .opacity(cardOpacity)
            .padding(.top, 34)
        }

        Spacer(minLength: 0)
      }
      .padding(40)

      if phase != .card {
        skipHint
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { skipToCard() }
    .task { await play() }
    .onAppear(perform: installKeyMonitor)
    .onDisappear(perform: removeKeyMonitor)
  }

  // MARK: - Card

  private var introCard: some View {
    VStack(spacing: 10) {
      Text("Panopticon")
        .font(.system(size: 24, weight: .semibold))
        .foregroundColor(.white)

      Text(
        "It records your screen, turns the day into a timeline, and hands that to your agents. Everything stays on hardware you own."
      )
      .font(.system(size: 13.5))
      .foregroundColor(.white.opacity(0.62))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: 380)

      Button(action: begin) {
        Text("Set it up")
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundColor(Theme.Palette.onAccent)
          .padding(.horizontal, 22)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
              .fill(Theme.Palette.accent)
          )
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .keyboardShortcut(.defaultAction)
      .padding(.top, 8)
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 28)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    )
  }

  private var skipHint: some View {
    VStack {
      Spacer()
      Text("Click to skip")
        .font(.system(size: 11))
        .foregroundColor(.white.opacity(0.3))
        .padding(.bottom, 26)
    }
    .allowsHitTesting(false)
  }

  // MARK: - Sequence

  private func play() async {
    guard !didPlay else { return }
    didPlay = true

    if reduceMotion {
      // Same destination, no travel: honour the system preference rather than
      // playing a shortened version of the same motion.
      markOffset = 0
      markBlur = 0
      markScale = 1
      markOpacity = 1
      glowOpacity = 1
      revealCard(animated: false)
      return
    }

    // A beat of black before anything moves, so the rise reads as an entrance.
    try? await Task.sleep(nanoseconds: 420_000_000)
    phase = .rising

    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.15)) {
      markOffset = 0
      markOpacity = 1
      markScale = 1
    }
    withAnimation(.easeOut(duration: 0.9)) { markBlur = 0 }
    withAnimation(.easeInOut(duration: 1.3)) { glowOpacity = 1 }

    // Land slightly before the curve fully settles: the tap wants to coincide
    // with the mark visually arriving, not with the animation's last frame.
    try? await Task.sleep(nanoseconds: 900_000_000)
    guard phase == .rising else { return }
    playLandingCue()

    try? await Task.sleep(nanoseconds: 260_000_000)
    guard phase == .rising else { return }
    revealCard(animated: true)
  }

  private func revealCard(animated: Bool) {
    phase = .card
    guard animated else {
      cardOffset = 0
      cardOpacity = 1
      return
    }
    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.55)) {
      cardOffset = 0
      cardOpacity = 1
    }
  }

  /// Haptic tap plus a low note as the mark lands. The haptic is a no-op on Macs
  /// without a Force Touch trackpad, which is why it is not the only cue.
  private func playLandingCue() {
    NSHapticFeedbackManager.defaultPerformer.perform(
      .levelChange, performanceTime: .now)

    if let sound = NSSound(named: "Submarine") {
      // Quiet: this fires unprompted on first launch, so it should register
      // without being startling.
      sound.volume = 0.35
      sound.play()
    }
  }

  private func skipToCard() {
    guard phase != .card else { return }
    withAnimation(.easeOut(duration: 0.22)) {
      markOffset = 0
      markOpacity = 1
      markScale = 1
      markBlur = 0
      glowOpacity = 1
    }
    revealCard(animated: true)
  }

  private func begin() {
    removeKeyMonitor()
    onBegin()
  }

  // MARK: - Input

  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Any key skips ahead while the sequence is playing; once the card is up
      // its own default-action button handles Return.
      guard phase != .card else { return event }
      skipToCard()
      return nil
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }
}


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
