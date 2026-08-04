//
//  OnboardingFlow.swift
//  Panopticon
//

import Foundation
import ScreenCaptureKit
import SwiftUI

// Window manager removed - no longer needed!

struct OnboardingFlow: View {
  @AppStorage("onboardingStep") private var savedStepRawValue = 0
  @State private var step: OnboardingStep = OnboardingStepMigration.restoredStep()
  @AppStorage("didOnboard") private var didOnboard = false
  @AppStorage("selectedLLMProvider") private var selectedProvider: String = "gemini"
  @EnvironmentObject private var categoryStore: CategoryStore
  @State private var flowID = UUID().uuidString.lowercased()
  /// The opening sequence plays once per install. Persisted so a relaunch part
  /// way through setup does not replay it, which would be tedious rather than
  /// cinematic.
  @AppStorage("onboardingIntroPlayed") private var introPlayed = false

  private var onboardingFilledSegments: Int {
    switch step {
    case .welcome: return 0
    case .llmSelection: return 0
    case .llmSetup: return 1
    case .categories: return 2
    case .categoryColors: return 3
    case .screen: return 4
    case .completion: return 5
    }
  }

  private var showsProgressRing: Bool {
    step != .welcome && step != .llmSelection && step != .categoryColors
  }

  @ViewBuilder
  var body: some View {
    steps
      .onAppear(perform: presentIntroIfNeeded)
  }

  /// The film runs once, on the very first open, and fades to reveal the welcome
  /// screen underneath. It lives in its own screen-covering window so it can rise
  /// from below the Dock, so it is presented rather than composed into this view.
  private func presentIntroIfNeeded() {
    guard !introPlayed, step == .welcome, OnboardingIntroAsset.exists else {
      introPlayed = true
      return
    }
    introPlayed = true
    OnboardingIntroWindowController.shared.present(onFinish: {})
  }

  @ViewBuilder
  private var steps: some View {
    ZStack(alignment: .bottomLeading) {
      // NO NESTING! Just render the appropriate view directly - NO GROUP!
      switch step {
      case .welcome:
        OnboardingWelcomeStepView(onStart: { advance() })
          .frame(maxWidth: .infinity, maxHeight: .infinity)

      case .llmSelection:
        OnboardingPrototypeChooseProviderStep(
          hasPaidAI: false,
          flowID: flowID,
          flowVariant: "production_onboarding",
          onSelect: { providerTitle in
            // Map display title → internal provider ID
            let providerID: String
            switch providerTitle {
            case "ChatGPT or Claude": providerID = "chatgpt_claude"
            case "Google Gemini": providerID = "gemini"
            case "Local AI": providerID = "ollama"
            default: providerID = "gemini"
            }
            selectedProvider = providerID
            var props: [String: Any] = ["provider": providerID]
            if providerID == "ollama" {
              let localEngine = UserDefaults.standard.string(forKey: "llmLocalEngine") ?? "ollama"
              props["local_engine"] = localEngine
            }
            advance(extraProps: props)
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }

      case .llmSetup:
        // COMPLETELY STANDALONE - no parent constraints!
        LLMProviderSetupView(
          providerType: selectedProvider,
          onBack: {
            setStep(.llmSelection)
          },
          onComplete: {
            advance()
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }

      case .categories:
        OnboardingCategoryStepView(
          onBack: {
            setStep(.llmSetup)
          },
          onNext: {
            advance()
          }
        )
        .environmentObject(categoryStore)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }

      case .categoryColors:
        OnboardingCategoryColorStepView(
          onBack: {
            setStep(.categories)
          },
          onNext: {
            advance()
          }
        )
        .environmentObject(categoryStore)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      case .screen:
        ScreenRecordingPermissionView(
          onBack: {
            setStep(.categoryColors)
          },
          onNext: { advance() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }

      case .completion:
        CompletionView(
          onFinish: {
            // Create sample card BEFORE switching views (sync write)
            StorageManager.shared.createOnboardingCard()

            markStepCompleted(.completion)
            didOnboard = true
            savedStepRawValue = 0
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }
      }

      // Progress ring — bottom-left, always in tree (opacity toggle preserves @State)
      ProgressRingView(totalSegments: 6, filledSegments: onboardingFilledSegments)
        .opacity(showsProgressRing ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: showsProgressRing)
        .padding(.leading, 0)
        .padding(.bottom, 0)
        .allowsHitTesting(false)
    }
    .animation(.easeInOut(duration: 0.5), value: step)
    .onAppear {
      restoreSavedStep()
    }
    .background {
      // Flat canvas fills the window; the reference system has no
      // decorative background art.
      Theme.Palette.canvas.ignoresSafeArea()
    }
    .preferredColorScheme(.light)
  }

  private func restoreSavedStep() {
    let migratedValue = OnboardingStepMigration.migrateIfNeeded()
    if migratedValue != savedStepRawValue {
      savedStepRawValue = migratedValue
    }
    if let savedStep = OnboardingStep(rawValue: migratedValue) {
      if savedStep == .categories {
        prepareCategoriesForOnboardingIfNeeded()
      }
      step = savedStep
    }
  }

  private func setStep(_ newStep: OnboardingStep) {
    if newStep == .categories {
      prepareCategoriesForOnboardingIfNeeded()
    }
    step = newStep
    savedStepRawValue = newStep.rawValue
  }

  private func prepareCategoriesForOnboardingIfNeeded() {
    categoryStore.applyOnboardingPresetIfNeeded()
  }

  private func markStepCompleted(
    _ completedStep: OnboardingStep,
    extraProps: [String: Any] = [:]
  ) {
    var props: [String: Any] = ["step": completedStep.analyticsName]
    extraProps.forEach { key, value in
      props[key] = value
    }
  }

  private func advance(selectedRole: String? = nil, extraProps: [String: Any] = [:]) {
    switch step {
    case .welcome:
      markStepCompleted(step)
      setStep(.llmSelection)
    case .llmSelection:
      markStepCompleted(step, extraProps: extraProps)
      let nextStep: OnboardingStep = .llmSetup
      setStep(nextStep)
    case .llmSetup:
      markStepCompleted(step)
      setStep(.categories)
    case .categories:
      markStepCompleted(step)
      setStep(.categoryColors)
    case .categoryColors:
      markStepCompleted(step)
      setStep(.screen)
    case .screen:
      // Permission request is handled by ScreenRecordingPermissionView itself
      markStepCompleted(step)
      step.next()
      savedStepRawValue = step.rawValue

      // Only try to start recording if we already have permission
      if CGPreflightScreenCaptureAccess() {
        Task {
          do {
            // Verify we have permission
            _ = try await SCShareableContent.excludingDesktopWindows(
              false, onScreenWindowsOnly: true)
            // Start recording
            await MainActor.run {
              AppState.shared.setRecording(true)
            }
          } catch {
            // Permission not granted yet, that's ok
            // It will start after restart
            print("Will start recording after restart")
          }
        }
      }
    case .completion:
      didOnboard = true
      savedStepRawValue = 0  // Reset for next time
    }
  }

}

/// Wizard step order
enum OnboardingStep: Int, CaseIterable {
  case welcome, llmSelection, llmSetup,
    categories, categoryColors, screen, completion

  var analyticsName: String {
    switch self {
    case .welcome:
      return "welcome"
    case .llmSelection:
      return "llm_selection"
    case .llmSetup:
      return "llm_setup"
    case .categories:
      return "categories"
    case .categoryColors:
      return "category_colors"
    case .screen:
      return "screen_recording"
    case .completion:
      return "completion"
    }
  }

  static func hasPassedScreenRecordingStep(rawValue: Int) -> Bool {
    guard let step = OnboardingStep(rawValue: rawValue) else { return false }
    return step.rawValue > OnboardingStep.screen.rawValue
  }

  mutating func next() { self = OnboardingStep(rawValue: rawValue + 1)! }
}

enum OnboardingStepMigration {
  static let schemaVersionKey = "onboardingStepSchemaVersion"
  private static let onboardingStepKey = "onboardingStep"
  /// v2 inserted `welcome` ahead of `llmSelection`, shifting every raw value up
  /// by one.
  static let currentVersion = 2

  @discardableResult
  static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Int {
    let storedVersion = defaults.integer(forKey: schemaVersionKey)
    if storedVersion < currentVersion {
      // Only installs that actually ran v1 carry v1 numbering. A fresh install
      // has no stamped version and no saved step, and must stay at 0 so it opens
      // on the welcome rather than being pushed past it.
      if storedVersion == 1, defaults.object(forKey: onboardingStepKey) != nil {
        defaults.set(defaults.integer(forKey: onboardingStepKey) + 1, forKey: onboardingStepKey)
      }
      defaults.set(currentVersion, forKey: schemaVersionKey)
    }
    return defaults.integer(forKey: onboardingStepKey)
  }

  static func restoredStep(defaults: UserDefaults = .standard) -> OnboardingStep {
    OnboardingStep(rawValue: migrateIfNeeded(defaults: defaults)) ?? .welcome
  }
}

struct OnboardingCategoryColorStepView: View {
  let onBack: () -> Void
  let onNext: () -> Void
  @EnvironmentObject private var categoryStore: CategoryStore

  var body: some View {
    VStack(spacing: 32) {
      ColorOrganizerRoot(
        presentationStyle: .embedded,
        flowMode: .colorsOnly,
        onBack: onBack,
        onDismiss: {
          onNext()
        },
        analyticsSurface: "onboarding"
      )
      .environmentObject(categoryStore)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 600)
    }
    .padding(.horizontal, 40)
    .padding(.vertical, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}




struct CompletionView: View {
  let onFinish: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text("Panopticon")
        .font(.system(size: 28, weight: .semibold))
        .foregroundColor(Theme.Palette.ink)
        .tracking(-0.5)

      // Title section
      VStack(spacing: 8) {
        Text("You are ready to go!")
          .font(.system(size: 36, weight: .semibold))
          .foregroundColor(.black.opacity(0.9))

        Text(
          "To get useful insights, let Panopticon run in the background for an hour or two to gather enough context, then check back in."
        )
        .font(.system(size: 15))
        .foregroundColor(.black.opacity(0.6))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      }

      PanopticonSurfaceButton(
        action: {
          onFinish()
        },
        content: {
          Text("Launch Panopticon")
            .font(.system(size: 16))
            .fontWeight(.semibold)
        },
        background: Theme.Palette.ink,
        foreground: .white,
        borderColor: .clear,
        cornerRadius: 8,
        horizontalPadding: 40,
        verticalPadding: 14,
        minWidth: 200,
        isFilledStyle: true
      )
      .padding(.top, 16)
    }
    .padding(.horizontal, 48)
    .padding(.vertical, 60)
    .frame(maxWidth: 720)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct OnboardingFlow_Previews: PreviewProvider {
  static var previews: some View {
    OnboardingFlow()
      .environmentObject(AppState.shared)
      .frame(width: 1200, height: 800)
  }
}
