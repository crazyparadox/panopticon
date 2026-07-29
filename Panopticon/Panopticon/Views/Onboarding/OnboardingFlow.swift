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
  @AppStorage("onboardingHasPaidAI") private var savedHasPaidAISelection = ""
  @EnvironmentObject private var categoryStore: CategoryStore
  @State private var userHasPaidAI: Bool? = OnboardingFlow.loadSavedHasPaidAISelection()
  @State private var flowID = UUID().uuidString.lowercased()

  private var onboardingFilledSegments: Int {
    switch step {
    case .introVideo: return 0
    case .roleSelection: return 0
    case .downloadReason: return 1
    case .preferences: return 2
    case .llmSelection: return 3
    case .llmSetup: return 4
    case .categories: return 5
    case .categoryColors: return 6
    case .screen: return 7
    case .completion: return 8
    }
  }

  private var showsProgressRing: Bool {
    step != .introVideo && step != .llmSelection && step != .categoryColors
  }

  @ViewBuilder
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      // NO NESTING! Just render the appropriate view directly - NO GROUP!
      switch step {
      case .introVideo:
        OnboardingPrototypeVideoIntroStep(
          videoName: "PanopticonOnboarding",
          onPlaybackStarted: {
          },
          onPlaybackCompleted: { reason in
            advance()
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onAppear {
          if !UserDefaults.standard.bool(forKey: "onboardingStarted") {
            UserDefaults.standard.set(true, forKey: "onboardingStarted")
          }
        }

      case .roleSelection:
        OnboardingPrototypeRoleSelectionStep(
          onContinue: { selectedRole in
            categoryStore.setOnboardingRole(selectedRole)
            advance(selectedRole: selectedRole)
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onAppear {
        }

      case .downloadReason:
        OnboardingPrototypeDownloadReasonStep(
          onContinue: { reasons, otherDetail in
            var payload: [String: Any] = [
              "reasons": reasons.map(\.analyticsValue),
              "surface": "onboarding_download_reason",
            ]

            if let otherDetail, !otherDetail.isEmpty {
              payload["other_detail"] = otherDetail
            }

            advance(extraProps: payload)
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }

      case .preferences:
        OnboardingPrototypePreferencesStep(
          onContinue: { hasPaidAI in
            userHasPaidAI = hasPaidAI
            savedHasPaidAISelection = hasPaidAI ? "yes" : "no"
            advance(extraProps: ["has_paid_ai": hasPaidAI])
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }

      case .llmSelection:
        OnboardingPrototypeChooseProviderStep(
          hasPaidAI: userHasPaidAI ?? false,
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
            savedHasPaidAISelection = ""
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
        }
      }

      // Progress ring — bottom-left, always in tree (opacity toggle preserves @State)
      ProgressRingView(totalSegments: 9, filledSegments: onboardingFilledSegments)
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
    userHasPaidAI = persistedHasPaidAISelection
    if let savedStep = OnboardingStep(rawValue: migratedValue) {
      if savedStep == .categories {
        prepareCategoriesForOnboardingIfNeeded()
      }
      step = savedStep
    }
  }

  private var persistedHasPaidAISelection: Bool? {
    Self.decodeHasPaidAISelection(savedHasPaidAISelection)
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
    case .introVideo:
      markStepCompleted(step)
      step.next()
      savedStepRawValue = step.rawValue
    case .roleSelection:
      let extraProps = selectedRole.map { ["role": $0] } ?? [:]
      markStepCompleted(step, extraProps: extraProps)
      step.next()
      savedStepRawValue = step.rawValue
    case .downloadReason:
      markStepCompleted(step, extraProps: extraProps)
      step.next()
      savedStepRawValue = step.rawValue
    case .preferences:
      markStepCompleted(step, extraProps: extraProps)
      step.next()
      savedStepRawValue = step.rawValue
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

  private static func loadSavedHasPaidAISelection(defaults: UserDefaults = .standard) -> Bool? {
    decodeHasPaidAISelection(defaults.string(forKey: "onboardingHasPaidAI") ?? "")
  }

  private static func decodeHasPaidAISelection(_ value: String) -> Bool? {
    switch value {
    case "yes":
      return true
    case "no":
      return false
    default:
      return nil
    }
  }

}

/// Wizard step order
enum OnboardingStep: Int, CaseIterable {
  case introVideo, roleSelection, downloadReason, preferences, llmSelection, llmSetup,
    categories, categoryColors, screen, completion

  var analyticsName: String {
    switch self {
    case .introVideo:
      return "intro_video"
    case .roleSelection:
      return "role_selection"
    case .downloadReason:
      return "download_reason"
    case .preferences:
      return "preferences"
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
  static let currentVersion = 1

  /// Panopticon ships with a fresh bundle identifier, so there is no legacy
  /// Panopticon onboarding state to migrate. This only stamps the current schema
  /// version and returns the stored step.
  @discardableResult
  static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Int {
    defaults.set(currentVersion, forKey: schemaVersionKey)
    return defaults.integer(forKey: onboardingStepKey)
  }

  static func restoredStep(defaults: UserDefaults = .standard) -> OnboardingStep {
    OnboardingStep(rawValue: migrateIfNeeded(defaults: defaults)) ?? .introVideo
  }
}

struct WelcomeView: View {
  let fullText: String
  @Binding var textOpacity: Double
  @Binding var timelineOffset: CGFloat
  let onStart: () -> Void

  var body: some View {
    ZStack {
      // Text and button container
      VStack {
        VStack(spacing: 20) {
          Image("PanopticonLogoMainApp")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(height: 64)
            .opacity(textOpacity)

          Text(fullText)
            .font(.system(size: 36, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundColor(.black.opacity(0.8))
            .padding(.horizontal, 20)
            .minimumScaleFactor(0.5)
            .lineLimit(3)
            .frame(minHeight: 100)
            .opacity(textOpacity)
            .onAppear {
              withAnimation(.easeOut(duration: 0.6)) {
                textOpacity = 1
              }
            }

          PanopticonSurfaceButton(
            action: onStart,
            content: { Text("Start").font(.system(size: 16)).fontWeight(.semibold) },
            background: Theme.Palette.ink,
            foreground: .white,
            borderColor: .clear,
            cornerRadius: 8,
            horizontalPadding: 28,
            verticalPadding: 14,
            minWidth: 160,
            isFilledStyle: true
          )
          .opacity(textOpacity)
          .animation(.easeIn(duration: 0.3).delay(0.4), value: textOpacity)
        }
        .padding(.top, 20)

        Spacer()
      }
      .zIndex(1)

      // Timeline image
      VStack {
        Spacer()
        Image("OnboardingTimeline")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 800)
          .offset(y: timelineOffset)
          .opacity(timelineOffset > 0 ? 0 : 1)
          .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0).delay(0.3))
            {
              timelineOffset = 0
            }
          }
      }
    }
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

struct OnboardingPrototypeDownloadReasonStep: View {
  let onContinue: ([DownloadReasonOption], String?) -> Void

  @State private var shuffledReasons = DownloadReasonOption.randomizedConcreteOptions()
  @State private var selectedReasons: Set<DownloadReasonOption> = []
  @State private var otherText = ""

  private var options: [DownloadReasonOption] {
    shuffledReasons + [.other]
  }

  private var trimmedOtherText: String {
    otherText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canContinue: Bool {
    guard !selectedReasons.isEmpty else { return false }
    if selectedReasons.contains(.other) {
      return !trimmedOtherText.isEmpty
    }
    return true
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer()
        .frame(height: 126)

      VStack(spacing: 22) {
        VStack(spacing: 4) {
          Text("What are you hoping to get out of Panopticon?")
            .font(.system(size: 20))
            .foregroundColor(Theme.Palette.ink2)

          Text("This helps personalize the experience for you.")
            .font(.system(size: 16))
            .foregroundColor(Theme.Palette.ink2.opacity(0.78))
        }
        .multilineTextAlignment(.center)

        VStack(spacing: 8) {
          ForEach(options) { option in
            downloadReasonRow(option)
          }
        }

        otherField
      }
      .frame(maxWidth: 760)
      .padding(.horizontal, 24)

      Spacer()

      PanopticonSurfaceButton(
        action: {
          let selectedInDisplayOrder = options.filter { selectedReasons.contains($0) }
          let detail = selectedReasons.contains(.other) ? trimmedOtherText : nil
          onContinue(selectedInDisplayOrder, detail)
        },
        content: {
          Text("Continue")
            .font(.system(size: 14))
            .fontWeight(.semibold)
        },
        background: Theme.Palette.ink,
        foreground: .white,
        borderColor: .clear,
        cornerRadius: 8,
        horizontalPadding: 59,
        verticalPadding: 12,
        minWidth: 234,
        isFilledStyle: true
      )
      .opacity(canContinue ? 1.0 : 0.4)
      .allowsHitTesting(canContinue)
      .animation(.easeInOut(duration: 0.2), value: canContinue)

      Spacer()
        .frame(height: 60)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeInOut(duration: 0.2), value: selectedReasons)
  }

  private func downloadReasonRow(_ option: DownloadReasonOption) -> some View {
    let isSelected = selectedReasons.contains(option)

    return Button {
      toggle(option)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(Theme.Palette.ink)

        Text(option.displayName)
          .font(.system(size: 15))
          .foregroundColor(Theme.Palette.ink)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? Theme.Palette.accentTint.opacity(0.48) : Color.white.opacity(0.42))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(isSelected ? Theme.Palette.accentTint : Theme.Palette.line, lineWidth: 1)
      )
      .shadow(
        color: isSelected
          ? Theme.Palette.accent.opacity(0.22)
          : Theme.Palette.ink3.opacity(0.12),
        radius: isSelected ? 3 : 2,
        x: 0,
        y: 0
      )
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
  }

  private var otherField: some View {
    TextField("Tell me more", text: $otherText)
      .font(.system(size: 16))
      .foregroundColor(Theme.Palette.ink)
      .textFieldStyle(.plain)
      .padding(.horizontal, 12)
      .frame(height: 36)
      .background(Color.white.opacity(0.42))
      .cornerRadius(5)
      .overlay(
        RoundedRectangle(cornerRadius: 5)
          .stroke(Theme.Palette.line, lineWidth: 1)
      )
      .shadow(
        color: Theme.Palette.ink3.opacity(0.15),
        radius: 2, x: 0, y: 0
      )
      .opacity(selectedReasons.contains(.other) ? 1 : 0)
      .disabled(!selectedReasons.contains(.other))
      .allowsHitTesting(selectedReasons.contains(.other))
      .frame(maxWidth: .infinity)
  }

  private func toggle(_ option: DownloadReasonOption) {
    if selectedReasons.contains(option) {
      selectedReasons.remove(option)
      if option == .other {
        otherText = ""
      }
    } else {
      selectedReasons.insert(option)
    }
  }
}

enum DownloadReasonOption: CaseIterable, Identifiable, Hashable {
  case automaticLog
  case proofOfWork
  case cutDistractions
  case productiveFocused
  case automatedManualTracking
  case openSourcePrivate
  case other

  var id: String { analyticsValue }

  static func randomizedConcreteOptions() -> [DownloadReasonOption] {
    allCases.filter { $0 != .other }.shuffled()
  }

  var displayName: String {
    switch self {
    case .automaticLog:
      return "To keep an automatic log of what I worked on"
    case .proofOfWork:
      return "To make my work more visible for standups, reviews, or promotions"
    case .cutDistractions:
      return "To find and cut distractions"
    case .productiveFocused:
      return "To be more productive or focused"
    case .automatedManualTracking:
      return "I was already tracking this manually and wanted it automated"
    case .openSourcePrivate:
      return "I wanted a tracker that's open source and keeps my data private"
    case .other:
      return "Other"
    }
  }

  var analyticsValue: String {
    switch self {
    case .automaticLog:
      return "automatic_log"
    case .proofOfWork:
      return "proof_of_work"
    case .cutDistractions:
      return "cut_distractions"
    case .productiveFocused:
      return "productive_focused"
    case .automatedManualTracking:
      return "automated_manual_tracking"
    case .openSourcePrivate:
      return "open_source_private"
    case .other:
      return "other"
    }
  }
}


struct CompletionView: View {
  let onFinish: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image("PanopticonLogoMainApp")
        .resizable()
        .renderingMode(.original)
        .scaledToFit()
        .frame(height: 64)

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
