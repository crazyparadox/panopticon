//
//  OnboardingIntroVideo.swift
//  Panopticon
//
//  Optional pre-rendered intro. Drop a file named `panopticon-intro.mov` (or
//  .mp4) into the app's resources and the opening sequence plays it instead of
//  the coded animation; with no file present nothing changes. This is how Coast
//  does its intro, so it is the same handoff point if we render one.
//

import AVFoundation
import AppKit
import SwiftUI

enum OnboardingIntroAsset {
  /// Located by name so adding the file is the only step required. Checked for
  /// each presentation rather than cached, since it never changes at runtime.
  static var url: URL? {
    for ext in ["mov", "mp4", "m4v"] {
      if let url = Bundle.main.url(forResource: "panopticon-intro", withExtension: ext) {
        return url
      }
    }
    return nil
  }

  static var exists: Bool { url != nil }
}

/// Plays the intro once and reports when it finishes. Uses an AVPlayerLayer
/// directly rather than AVPlayerView: the latter brings playback chrome and
/// background colours that would show through a full-screen takeover.
struct OnboardingIntroVideoView: NSViewRepresentable {
  let url: URL
  let onEnded: () -> Void

  func makeNSView(context: Context) -> PlayerHostView {
    let view = PlayerHostView()
    view.configure(url: url, onEnded: onEnded)
    return view
  }

  func updateNSView(_ nsView: PlayerHostView, context: Context) {}

  static func dismantleNSView(_ nsView: PlayerHostView, coordinator: ()) {
    nsView.teardown()
  }

  final class PlayerHostView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?
    private var onEnded: (() -> Void)?

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer = CALayer()
      layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      wantsLayer = true
      layer = CALayer()
      layer?.backgroundColor = .clear
    }

    func configure(url: URL, onEnded: @escaping () -> Void) {
      self.onEnded = onEnded

      let player = AVPlayer(url: url)
      // Nothing to gain from looping or scrubbing; it plays once.
      player.actionAtItemEnd = .pause
      let playerLayer = AVPlayerLayer(player: player)
      // Fill: the render is one fixed size and the window is whatever the
      // display is, so cropping the edges beats letterboxing a takeover.
      playerLayer.videoGravity = .resizeAspectFill
      playerLayer.frame = bounds
      layer?.addSublayer(playerLayer)

      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: player.currentItem, queue: .main
      ) { [weak self] _ in
        self?.onEnded?()
      }

      self.player = player
      self.playerLayer = playerLayer
      player.play()
    }

    override func layout() {
      super.layout()
      playerLayer?.frame = bounds
    }

    func teardown() {
      player?.pause()
      if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
      endObserver = nil
      player = nil
      playerLayer?.removeFromSuperlayer()
      playerLayer = nil
    }

    deinit { teardown() }
  }
}
