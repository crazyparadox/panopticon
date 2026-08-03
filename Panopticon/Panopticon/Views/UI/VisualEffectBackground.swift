//
//  VisualEffectBackground.swift
//  Panopticon
//
//  Real window vibrancy. Two pieces are needed and neither works alone: an
//  NSVisualEffectView blending with what is *behind* the window, and a window
//  that is actually non-opaque so there is something behind it to sample. A
//  gradient can imitate the colour of a desktop showing through, but it cannot
//  track the wallpaper, move with the window, or pick up windows underneath.
//

import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .underWindowBackground
  var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blendingMode
    // `.active` keeps the blur alive when the app loses focus; the default
    // follows window state and flattens to grey the moment you click away.
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = material
    nsView.blendingMode = blendingMode
    nsView.state = .active
  }
}

/// Makes the hosting window non-opaque with a clear background, which is what
/// lets `.behindWindow` blending sample the desktop. SwiftUI's `Window` scene
/// has no modifier for this, so it is reached through the NSWindow itself.
struct TranslucentWindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = ConfiguratorView()
    view.isHidden = true
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class ConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window else { return }
      window.isOpaque = false
      window.backgroundColor = .clear
      // Without this the titlebar area paints its own opaque material over the
      // vibrancy, leaving a visible band across the top.
      window.titlebarAppearsTransparent = true
      // No traffic lights. The window is still closable with Cmd+W and the app
      // stays reachable from the menu bar item.
      for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(button)?.isHidden = true
      }
    }
  }
}
