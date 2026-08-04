//
//  OnboardingIntroWindow.swift
//  Panopticon
//
//  The opening sequence is its own window, not a view inside the app window, so
//  it can rise from below the Dock and cover the whole screen. This follows
//  Coast: the window is a bare full-screen player for one pre-rendered movie
//  composited over the desktop, and when the movie ends the window fades out and
//  setup is already underneath.
//

import AppKit
import SwiftUI

/// Borderless windows refuse key status by default, which would leave the intro
/// unable to take Escape or Return.
final class KeyableBorderlessWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@MainActor
final class OnboardingIntroWindowController {
  static let shared = OnboardingIntroWindowController()

  private var window: KeyableBorderlessWindow?
  private var onFinish: (() -> Void)?

  private init() {}

  var isPresenting: Bool { window != nil }

  /// Slides a full-screen panel up from beneath the Dock, then plays the intro
  /// inside it. `onFinish` fires once it has slid back out.
  func present(onFinish: @escaping () -> Void) {
    guard window == nil else { return }
    guard let screen = NSScreen.main else {
      onFinish()
      return
    }
    self.onFinish = onFinish

    let target = screen.frame
    // Start fully below the visible screen, so the rise begins from behind the
    // Dock rather than from the bottom of a window.
    let start = CGRect(
      x: target.minX, y: target.minY - target.height,
      width: target.width, height: target.height)

    let window = KeyableBorderlessWindow(
      contentRect: start, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.isMovable = false
    // Above the Dock and the menu bar: this is a takeover, and stopping short of
    // them would show seams at the screen edges.
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    // Deliberately capturable. The backdrop dim is hidden from capture because it
    // is on screen during normal recording, but the intro only plays during
    // first-run setup, before recording has been granted or started, so there is
    // nothing to pollute. Hiding it would only stop us screen-recording the
    // sequence for a demo, which is worth more than guarding a case that cannot
    // occur.

    let root = OnboardingIntroContent(
      onFinished: { [weak self] in self?.dismiss() }
    )
    let host = NSHostingView(rootView: root)
    host.frame = CGRect(origin: .zero, size: start.size)
    host.autoresizingMask = [.width, .height]
    window.contentView = host

    self.window = window
    window.makeKeyAndOrderFront(nil)

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.85
      // Decelerating: fast off the mark, settling at the top.
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
      window.animator().setFrame(target, display: true)
    }
  }

  func dismiss() {
    guard let window else { return }
    self.window = nil
    let finish = onFinish
    onFinish = nil

    // Fades out in place. Sliding it back down drew attention to the panel as an
    // object, when by this point the film should simply stop being there.
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.55
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        window.animator().alphaValue = 0
      },
      completionHandler: {
        window.orderOut(nil)
        finish?()
      })
  }
}
