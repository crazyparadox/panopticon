//
//  BackdropBlurController.swift
//  Panopticon
//
//  Blurs everything behind the main window while Panopticon is in front, so the
//  timeline reads as the focus rather than one window among many.
//
//  This is done with a borderless, non-opaque window per screen carrying an
//  NSVisualEffectView in `.behindWindow` mode: the compositor blurs whatever is
//  underneath it. No screen capture is involved, so it needs no permission and
//  costs nothing to keep on screen.
//

import AppKit

@MainActor
final class BackdropBlurController {
  static let shared = BackdropBlurController()

  private var panels: [NSWindow] = []
  private var isShown = false

  private init() {}

  func attach() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(appActivated),
      name: NSApplication.didBecomeActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(appDeactivated),
      name: NSApplication.didResignActiveNotification, object: nil)
    // Screens come and go (docking, display sleep); rebuild to match.
    center.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    if NSApp.isActive { show() }
  }

  @objc private func appActivated() { show() }
  @objc private func appDeactivated() { hide() }

  @objc private func screensChanged() {
    guard isShown else { return }
    hide()
    show()
  }

  func show() {
    // Only meaningful when there is a real window to sit behind.
    guard let main = Self.mainWindow() else { return }
    if isShown {
      restack(behind: main)
      return
    }

    panels = NSScreen.screens.map { screen in
      let panel = NSPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false)
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      // Purely decorative: clicks must reach whatever is underneath.
      panel.ignoresMouseEvents = true
      panel.isMovable = false
      // Stays out of Mission Control, window cycling and screenshots of other
      // apps' windows; follows the user across spaces.
      panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
      panel.setFrame(screen.frame, display: false)

      let effect = NSVisualEffectView(frame: screen.frame)
      effect.material = .fullScreenUI
      effect.blendingMode = .behindWindow
      // `.active` keeps the blur up even though the panel never becomes key.
      effect.state = .active
      effect.autoresizingMask = [.width, .height]
      panel.contentView = effect

      panel.orderFront(nil)
      return panel
    }

    isShown = true
    restack(behind: main)
  }

  func hide() {
    panels.forEach { $0.orderOut(nil) }
    panels.removeAll()
    isShown = false
  }

  /// Keep every panel directly beneath the main window: above other apps, never
  /// over Panopticon itself.
  private func restack(behind main: NSWindow) {
    for panel in panels {
      panel.order(.below, relativeTo: main.windowNumber)
    }
  }

  private static func mainWindow() -> NSWindow? {
    NSApp.windows.first {
      $0.isVisible && !($0 is NSPanel) && $0.contentView != nil
        && $0.styleMask.contains(.titled)
    }
  }
}
