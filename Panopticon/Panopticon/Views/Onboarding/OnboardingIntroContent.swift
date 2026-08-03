//
//  OnboardingIntroContent.swift
//  Panopticon
//
//  What plays inside the full-screen intro window. The panel has already risen
//  from below the Dock by the time this appears, so the sequence here is the mark
//  resolving, a latch cue as it lands, then the card.
//

import AppKit
import SwiftUI

struct OnboardingIntroContent: View {
  let onBegin: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum Phase { case rising, card }

  /// A bundled render takes precedence over the coded sequence. Resolved once so
  /// the branch cannot change mid-play.
  private let introVideo = OnboardingIntroAsset.url

  @State private var phase: Phase = .rising
  @State private var markOpacity: Double = 0
  @State private var markBlur: CGFloat = 12
  @State private var markScale: CGFloat = 0.9
  @State private var markLift: CGFloat = 40
  @State private var glowOpacity: Double = 0
  @State private var cardOffset: CGFloat = 30
  @State private var cardOpacity: Double = 0
  @State private var didPlay = false
  @State private var keyMonitor: Any?

  var body: some View {
    ZStack {
      // 90% rather than solid, so the desktop is still faintly present behind
      // the takeover instead of being replaced outright.
      Color.black.opacity(0.9)

      RadialGradient(
        colors: [Theme.Palette.accent.opacity(0.20), .clear],
        center: .center, startRadius: 0, endRadius: 520
      )
      .opacity(glowOpacity)
      .allowsHitTesting(false)

      if let introVideo, phase == .rising {
        OnboardingIntroVideoView(url: introVideo, onEnded: { reveal(animated: true) })
          .ignoresSafeArea()
          .transition(.opacity)
      }

      VStack(spacing: 0) {
        if introVideo == nil {
          PanopticonMark(size: 108)
            .scaleEffect(markScale)
            .blur(radius: markBlur)
            .opacity(markOpacity)
            .offset(y: markLift)
        }

        if phase == .card {
          introCard
            .offset(y: cardOffset)
            .opacity(cardOpacity)
            .padding(.top, 40)
        }
      }

      if phase == .rising {
        VStack {
          Spacer()
          Text("Click anywhere to skip")
            .font(.system(size: 11.5))
            .foregroundColor(.white.opacity(0.28))
            .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
      }
    }
    .ignoresSafeArea()
    .contentShape(Rectangle())
    .onTapGesture { skip() }
    .task { await play() }
    .onAppear(perform: installKeyMonitor)
    .onDisappear(perform: removeKeyMonitor)
  }

  private var introCard: some View {
    VStack(spacing: 12) {
      Text("Panopticon")
        .font(.system(size: 27, weight: .semibold))
        .foregroundColor(.white)

      Text(
        "It records your screen, turns the day into a timeline, and hands that to your agents. Everything stays on hardware you own."
      )
      .font(.system(size: 14))
      .foregroundColor(.white.opacity(0.6))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: 420)

      Button(action: begin) {
        Text("Set it up")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(Theme.Palette.onAccent)
          .padding(.horizontal, 26)
          .padding(.vertical, 11)
          .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
              .fill(Theme.Palette.accent)
          )
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .keyboardShortcut(.defaultAction)
      .padding(.top, 10)
    }
    .padding(.horizontal, 40)
    .padding(.vertical, 32)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(0.055))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(Color.white.opacity(0.11), lineWidth: 1)
    )
  }

  // MARK: - Sequence

  private func play() async {
    guard !didPlay else { return }
    didPlay = true

    // A bundled render carries its own timing and audio; the view just waits for
    // it to report the end.
    if introVideo != nil { return }

    if reduceMotion {
      markOpacity = 1
      markBlur = 0
      markScale = 1
      markLift = 0
      glowOpacity = 1
      reveal(animated: false)
      return
    }

    // The window is still travelling up for the first ~850ms. Let it arrive
    // before the mark resolves, so the two movements read as one gesture rather
    // than competing.
    try? await Task.sleep(nanoseconds: 520_000_000)

    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.95)) {
      markOpacity = 1
      markScale = 1
      markLift = 0
    }
    withAnimation(.easeOut(duration: 0.75)) { markBlur = 0 }
    withAnimation(.easeInOut(duration: 1.2)) { glowOpacity = 1 }

    try? await Task.sleep(nanoseconds: 700_000_000)
    guard phase == .rising else { return }
    playLatchCue()

    try? await Task.sleep(nanoseconds: 240_000_000)
    guard phase == .rising else { return }
    reveal(animated: true)
  }

  private func reveal(animated: Bool) {
    phase = .card
    guard animated else {
      cardOffset = 0
      cardOpacity = 1
      return
    }
    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)) {
      cardOffset = 0
      cardOpacity = 1
    }
  }

  /// Haptic plus a low note as the mark settles. Dia ships its own latch and
  /// shimmer samples for this; those are their assets, so a system sound stands in
  /// until we record our own. The haptic is a no-op without a Force Touch
  /// trackpad, which is why it is not the only cue.
  private func playLatchCue() {
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    if let sound = NSSound(named: "Submarine") {
      sound.volume = 0.35
      sound.play()
    }
  }

  private func skip() {
    guard phase == .rising else { return }
    // With a render playing there is no coded state to fast-forward; cut to the
    // card and let the player be torn down.
    if introVideo != nil {
      reveal(animated: true)
      return
    }
    withAnimation(.easeOut(duration: 0.2)) {
      markOpacity = 1
      markScale = 1
      markBlur = 0
      markLift = 0
      glowOpacity = 1
    }
    reveal(animated: true)
  }

  private func begin() {
    removeKeyMonitor()
    onBegin()
  }

  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if phase == .rising {
        skip()
        return nil
      }
      // Escape leaves the intro entirely once the card is up; Return is handled
      // by the button's own default-action binding.
      if event.keyCode == 53 {
        begin()
        return nil
      }
      return event
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }
}
