//
//  PanopticonApp.swift
//  Panopticon
//
//  Panopticon runs as a background recorder. The in-app surface is minimal:
//  onboarding, a read-only timeline for sanity-checking what the recorder
//  produces, and settings. The data itself is meant to be read by external
//  agents over MCP.
//

import SwiftUI


@main
struct PanopticonApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @AppStorage("didOnboard") private var didOnboard = false
  @StateObject private var categoryStore = CategoryStore()

  var body: some Scene {
    Window("Panopticon", id: "main") {
      Group {
        if didOnboard {
          MainView()
            .environmentObject(AppState.shared)
            .environmentObject(categoryStore)
        } else {
          OnboardingFlow()
            .environmentObject(AppState.shared)
            .environmentObject(categoryStore)
        }
      }
      .background {
        Theme.Palette.canvas.ignoresSafeArea()
        MainWindowRegistrationView()
      }
      .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
    .defaultSize(width: 1000, height: 660)
    .commands {
      // Single-window app: drop "New Window".
      CommandGroup(replacing: .newItem) {}

      CommandGroup(after: .appInfo) {
        Divider()
        Button("Reset Onboarding") {
          let defaults = UserDefaults.standard
          defaults.set(false, forKey: "didOnboard")
          defaults.set(0, forKey: "onboardingStep")
          defaults.removeObject(forKey: CategoryStore.StoreKeys.onboardingSelectedRole)
          defaults.removeObject(forKey: CategoryStore.StoreKeys.onboardingAppliedCategoryPreset)
          defaults.removeObject(forKey: CategoryStore.StoreKeys.onboardingCategoriesCustomized)
          defaults.set("gemini", forKey: "selectedLLMProvider")
          Task { @MainActor in
            AppDelegate.allowTermination = true
            NSApp.terminate(nil)
          }
        }
        .keyboardShortcut("R", modifiers: [.command, .shift])

        Button("Check for Updates…") {
          UpdaterManager.shared.checkForUpdates()
        }
      }
    }
  }
}

// MARK: - Notification Names

extension Notification.Name {
  static let timelineDataUpdated = Notification.Name("timelineDataUpdated")
  static let showTimelineFailureToast = Notification.Name("showTimelineFailureToast")
  static let showScreenRecordingPermissionNotice = Notification.Name(
    "showScreenRecordingPermissionNotice")
  static let openProvidersSettings = Notification.Name("openProvidersSettings")
}

@MainActor
final class MainWindowController {
  static let shared = MainWindowController()

  private var openWindowAction: OpenWindowAction?
  private var hasPendingOpenRequest = false

  func register(_ openWindowAction: OpenWindowAction) {
    self.openWindowAction = openWindowAction

    if hasPendingOpenRequest {
      hasPendingOpenRequest = false
      openWindowAction(id: "main")
    }
  }

  func showMainWindow() {
    guard let openWindowAction else {
      hasPendingOpenRequest = true
      return
    }

    openWindowAction(id: "main")
  }
}

private struct MainWindowRegistrationView: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onAppear {
        MainWindowController.shared.register(openWindow)
      }
  }
}
