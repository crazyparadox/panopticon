//
//  AppDelegate.swift
//  Panopticon
//

import AppKit
import Combine
import ScreenCaptureKit
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  // Controls whether the app is allowed to terminate.
  // Default is false so Cmd+Q/Dock/App menu quit will be cancelled
  // and the app will continue running in the background.
  static var allowTermination: Bool = false

  private var statusBar: StatusBarController!
  private var recorder: ScreenRecorder!
  private var powerObserver: NSObjectProtocol?
  private let screenshotShortcutTracker = ScreenshotShortcutTracker.shared
  private var deepLinkRouter: AppDeepLinkRouter?
  private var pendingDeepLinkURLs: [URL] = []

  override init() {
    UserDefaultsMigrator.migrateIfNeeded()
    super.init()
  }

  func applicationDidFinishLaunching(_ note: Notification) {
    // Block termination by default; only specific flows enable it.
    AppDelegate.allowTermination = false
    applySavedDockIconPreference()

    screenshotShortcutTracker.start()

    UserDefaults.standard.set(
      Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "", forKey: "lastRunBuild")
    statusBar = StatusBarController()
    LaunchAtLoginManager.shared.bootstrapDefaultPreference()
    deepLinkRouter = AppDeepLinkRouter()
    flushPendingDeepLinks()

    // Check if we've passed the screen recording permission step
    let onboardingStep = OnboardingStepMigration.migrateIfNeeded()
    let didOnboard = UserDefaults.standard.bool(forKey: "didOnboard")

    // Seed recording flag low, then create recorder so the first
    // transition to true will reliably start capture.
    AppState.shared.isRecording = false
    recorder = ScreenRecorder(autoStart: true)

    // Only attempt to start recording if we're past the screen step or fully onboarded.
    if didOnboard || OnboardingStep.hasPassedScreenRecordingStep(rawValue: onboardingStep) {
      // Onboarding complete - enable persistence and restore user preference
      AppState.shared.enablePersistence()

      // Try to start recording, but handle permission failures gracefully
      Task { [weak self] in
        guard let self else { return }
        guard ScreenRecordingPermissionNotice.isGranted else {
          AppState.shared.setRecording(false, persistPreference: false)
          if didOnboard {
            ScreenRecordingPermissionNotice.post(reason: "launch_preflight_missing")
          }
          return
        }

        do {
          // Check if we have permission by trying to access content
          _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
          // Permission granted - restore saved preference or default to ON
          let savedPref = AppState.shared.getSavedPreference()
          AppState.shared.setRecording(savedPref ?? true)
        } catch {
          // No permission or error - user must grant it in onboarding
          AppState.shared.setRecording(false, persistPreference: false)
          if didOnboard {
            ScreenRecordingPermissionNotice.post(reason: "launch_shareable_content_failed")
          }
          print("Screen recording permission not granted, skipping auto-start")
        }
      }
    } else {
      // Still in early onboarding: keep recording off and don't persist this state.
      AppState.shared.isRecording = false
    }

    // Start the timeline analysis background job
    setupAnalysis()

    // Start inactivity monitoring for idle reset
    InactivityMonitor.shared.start()

    // Generate daily recaps in the background (no in-app surface; read via MCP)
    DailyRecapScheduler.shared.start()

    // Push timeline + recaps to the hosted sync endpoint (if configured)
    CloudSyncManager.shared.start()

    powerObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willPowerOffNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated {
        AppDelegate.allowTermination = true
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if Self.allowTermination {
      return .terminateNow
    }
    // Soft-quit: hide windows and remove Dock icon, but keep status item + background tasks
    NSApp.hide(nil)
    NSApp.setActivationPolicy(.accessory)
    return .terminateCancel
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let router = deepLinkRouter else {
      pendingDeepLinkURLs.append(contentsOf: urls)
      return
    }
    for url in urls {
      _ = router.handle(url)
    }
  }

  private func flushPendingDeepLinks() {
    guard let router = deepLinkRouter, !pendingDeepLinkURLs.isEmpty else { return }
    let urls = pendingDeepLinkURLs
    pendingDeepLinkURLs.removeAll()
    for url in urls {
      _ = router.handle(url)
    }
  }

  private func applySavedDockIconPreference() {
    let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
  }

  /// Start timeline analysis as a background task.
  private func setupAnalysis() {
    // Perform after a short delay to ensure other initialization completes
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      AnalysisManager.shared.startAnalysisJob()
      print("AppDelegate: analysis job started")
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Checkpoint WAL to persist any pending database changes before quit.
    // Using .truncate to also reset the WAL file for a clean state.
    StorageManager.shared.checkpoint(mode: .truncate)

    screenshotShortcutTracker.stop()

    if let observer = powerObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      powerObserver = nil
    }
    DailyRecapScheduler.shared.stop()
    CloudSyncManager.shared.stop()
  }
}
