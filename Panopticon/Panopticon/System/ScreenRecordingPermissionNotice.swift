import AppKit
import CoreGraphics
import Foundation

enum ScreenRecordingPermissionNotice {
  /// CGPreflightScreenCaptureAccess() occasionally reports false while capture
  /// is plainly working (a stale per-process TCC answer). A real capture is
  /// stronger evidence than the preflight, so a frame saved within this window
  /// counts as granted. A genuine revocation makes captures fail, the window
  /// lapses, and the preflight answer takes over again.
  private static let captureEvidenceWindow: TimeInterval = 120
  private static let lock = NSLock()
  private static var lastSuccessfulCapture: Date?

  static var isGranted: Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    lock.lock()
    defer { lock.unlock() }
    guard let last = lastSuccessfulCapture else { return false }
    return Date().timeIntervalSince(last) < captureEvidenceWindow
  }

  /// Called by the recorder after a frame is captured and saved.
  static func recordSuccessfulCapture() {
    lock.lock()
    lastSuccessfulCapture = Date()
    lock.unlock()
  }

  static func post(reason: String) {
    let notification = {
      NotificationCenter.default.post(
        name: .showScreenRecordingPermissionNotice,
        object: nil,
        userInfo: ["reason": reason]
      )
    }

    if Thread.isMainThread {
      notification()
    } else {
      DispatchQueue.main.async(execute: notification)
    }
  }

  static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    else { return }

    NSWorkspace.shared.open(url)
  }
}
