//
//  BackdropDimController.swift
//  Panopticon
//
//  Dims everything behind the main window while Panopticon is in front, so the
//  timeline reads as the focus rather than one window among many.
//
//  A borderless, non-opaque panel per screen filled with translucent black. No
//  blur: blurring the desktop fought the window's own vibrancy, and a flat scrim
//  is both cheaper and easier to read against.
//

import AppKit

@MainActor
final class BackdropDimController {
  static let shared = BackdropDimController()

  private var panels: [NSWindow] = []
  private var isShown = false

  /// How dark the rest of the screen goes. Low enough that the desktop stays
  /// visible, high enough that the window is clearly the focus.
  private static let dimOpacity: CGFloat = 0.5

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

      let scrim = NSView(frame: screen.frame)
      scrim.wantsLayer = true
      scrim.layer?.backgroundColor =
        NSColor.black.withAlphaComponent(Self.dimOpacity).cgColor
      scrim.autoresizingMask = [.width, .height]
      panel.contentView = scrim

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
