//
//  OnboardingIntroVideo.swift
//  Panopticon
//
//  Plays the intro movie with its black pixels knocked out, so only the light in
//  it lands over the user's desktop. The source has no alpha channel (Coast's
//  doesn't either), so alpha is derived at playback from luminance: pure black
//  becomes fully transparent, bright areas stay opaque, and everything between
//  reads as a soft additive glow.
//
//  Drop a file named `panopticon-intro.mov` (or .mp4/.m4v) into the app's
//  resources and the opening plays it; with no file present nothing happens.
//

import AVFoundation
import AppKit
import CoreImage
import SwiftUI

enum OnboardingIntroAsset {
  /// Located by name so adding the file is the only step required.
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

/// Plays once and reports when it finishes. Uses an AVPlayerLayer directly
/// rather than AVPlayerView: the latter brings playback chrome and an opaque
/// background, both of which would defeat compositing over the desktop.
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
      prepareLayer()
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      prepareLayer()
    }

    private func prepareLayer() {
      wantsLayer = true
      layer = CALayer()
      layer?.isOpaque = false
      layer?.backgroundColor = .clear
    }

    func configure(url: URL, onEnded: @escaping () -> Void) {
      self.onEnded = onEnded

      let asset = AVURLAsset(url: url)
      let item = AVPlayerItem(asset: asset)
      let player = AVPlayer(playerItem: item)
      player.actionAtItemEnd = .pause

      // Built asynchronously: the synchronous initialiser loads the asset's
      // tracks on the calling thread, which would stall the first frame of the
      // window's rise. Playback starts either way; the knockout attaches as soon
      // as the composition is ready.
      Self.makeLumaToAlphaComposition(for: asset) { composition in
        item.videoComposition = composition
      }

      let playerLayer = AVPlayerLayer(player: player)
      playerLayer.videoGravity = .resizeAspectFill
      // Without both of these the layer paints an opaque black bed and the
      // knocked-out pixels never show the desktop.
      playerLayer.isOpaque = false
      playerLayer.backgroundColor = .clear
      playerLayer.frame = bounds
      layer?.addSublayer(playerLayer)

      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in
        self?.onEnded?()
      }

      self.player = player
      self.playerLayer = playerLayer
      player.play()
    }

    /// Maps luminance onto the alpha channel while leaving RGB alone. Core Image
    /// treats the result as premultiplied, which is what makes dark areas fall
    /// away additively rather than turning into grey haze.
    private static func makeLumaToAlphaComposition(
      for asset: AVAsset, completion: @escaping (AVVideoComposition?) -> Void
    ) {
      AVMutableVideoComposition.videoComposition(
        with: asset,
        applyingCIFiltersWithHandler: { request in
          let source = request.sourceImage
          guard let filter = CIFilter(name: "CIColorMatrix") else {
            request.finish(with: source, context: nil)
            return
          }
          filter.setValue(source, forKey: kCIInputImageKey)
          filter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
          filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
          filter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
          // Rec. 601 luma weights: matches how the eye reads brightness, so a
          // saturated blue does not punch a harder hole than an equally bright grey.
          filter.setValue(
            CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0), forKey: "inputAVector")
          request.finish(with: filter.outputImage ?? source, context: nil)
        },
        completionHandler: { composition, error in
          if let error {
            print("intro: luma knockout unavailable – \(error.localizedDescription)")
          }
          DispatchQueue.main.async { completion(composition) }
        })
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
