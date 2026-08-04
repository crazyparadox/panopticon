//
//  OnboardingIntroContent.swift
//  Panopticon
//
//  What plays inside the full-screen intro window: the film, composited over the
//  desktop with its black pixels knocked out. Nothing else. When it ends the
//  window fades and the first setup screen is already there underneath.
//
//  With no movie in the bundle there is nothing to play, so it reports done
//  immediately and setup begins as if there had been no intro at all.
//

import AppKit
import SwiftUI

struct OnboardingIntroContent: View {
  /// Called when the film has finished, or the user skipped it.
  let onFinished: () -> Void

  private let introVideo = OnboardingIntroAsset.url

  @State private var didFinish = false
  @State private var keyMonitor: Any?

  var body: some View {
    ZStack {
      // Nothing painted behind the player. The movie's blacks are knocked out at
      // playback so the desktop reads through them, and any backdrop here would
      // fill in exactly the pixels meant to fall away.
      if let introVideo {
        OnboardingIntroVideoView(url: introVideo, onEnded: finish)
          .ignoresSafeArea()
      }
    }
    .ignoresSafeArea()
    .contentShape(Rectangle())
    .onTapGesture { finish() }
    .onAppear(perform: start)
    .onDisappear(perform: removeKeyMonitor)
  }

  private func start() {
    guard introVideo != nil else {
      // Nothing to play: hand straight over rather than holding an empty window.
      finish()
      return
    }
    installKeyMonitor()
  }

  /// Guarded because the player's end notification, a click and a key can all
  /// arrive for the same dismissal.
  private func finish() {
    guard !didFinish else { return }
    didFinish = true
    removeKeyMonitor()
    onFinished()
  }

  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in
      finish()
      return nil
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }
}
