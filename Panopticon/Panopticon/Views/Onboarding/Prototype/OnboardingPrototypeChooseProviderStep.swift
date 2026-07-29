//
//  OnboardingPrototypeChooseProviderStep.swift
//  Panopticon
//

import SwiftUI

// MARK: - Provider Comparison Data

private enum ComparisonRating {
  case best, medium, basic

  /// Rating dots read green → amber → neutral, so the color carries the
  /// judgement even before the adjacent label is read.
  var dotGradient: LinearGradient {
    switch self {
    case .best:
      return LinearGradient(
        colors: [Theme.Palette.green, Theme.Palette.green.opacity(0.75)],
        startPoint: .top, endPoint: .bottom
      )
    case .medium:
      return LinearGradient(
        colors: [Theme.Palette.orange, Theme.Palette.orange.opacity(0.75)],
        startPoint: .top, endPoint: .bottom
      )
    case .basic:
      return LinearGradient(
        colors: [Theme.Palette.lineStrong, Theme.Palette.ink3],
        startPoint: .top, endPoint: .bottom
      )
    }
  }
}

private struct RatedValue {
  let text: String
  let rating: ComparisonRating
}

private struct ComparisonProvider: Identifiable {
  let id: String
  let title: String
  /// Passed to onSelect — kept identical to the old card titles so
  /// the selected_provider analytics values stay consistent.
  let selectionName: String
  let accuracy: RatedValue
  let subscription: String
  let ease: RatedValue
  let notes: String
}

// MARK: - Choose Provider Step

struct OnboardingPrototypeChooseProviderStep: View {
  let hasPaidAI: Bool
  let flowID: String
  let flowVariant: String
  let onSelect: (String) -> Void

  @State private var isChatCLIInstalled = false

  private static let providers: [ComparisonProvider] = [
    ComparisonProvider(
      id: "chatgpt_claude",
      title: "ChatGPT or Claude",
      selectionName: "ChatGPT or Claude",
      accuracy: RatedValue(text: "Best", rating: .best),
      subscription: "ChatGPT/Claude paid subscription",
      ease: RatedValue(text: "Requires installing CLI", rating: .medium),
      notes: "Suitable for ChatGPT/Claude subscriptions, uses less than 1% of your daily limit."
    ),
    ComparisonProvider(
      id: "gemini",
      title: "Gemini",
      selectionName: "Google Gemini",
      accuracy: RatedValue(text: "Medium", rating: .medium),
      subscription: "Free",
      ease: RatedValue(text: "API key", rating: .medium),
      notes: "Uses Gemini free tier."
    ),
    ComparisonProvider(
      id: "local",
      title: "Local AI",
      selectionName: "Local AI",
      accuracy: RatedValue(text: "Decent", rating: .basic),
      subscription: "Free",
      ease: RatedValue(text: "Extensive setup", rating: .basic),
      notes: "Requires 16GB+ RAM, 4GB free disk space, M1 or later chip preferred"
    ),
  ]

  var body: some View {
    VStack(spacing: 0) {
      Text("Choose a way to run Panopticon")
        .font(.system(size: 40, weight: .semibold))
        .tracking(-1.2)
        .multilineTextAlignment(.center)
        .foregroundColor(Theme.Palette.ink)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 45)

      comparisonTable
        .padding(.horizontal, 40)
        .transition(.opacity)

      Spacer(minLength: 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      let installed = await Task.detached(priority: .utility) {
        CLIDetector.isInstalled(.codex) || CLIDetector.isInstalled(.claude)
      }.value
      guard !Task.isCancelled else { return }
      isChatCLIInstalled = installed
    }
  }

  // MARK: - Comparison Table

  private var comparisonTable: some View {
    Grid(horizontalSpacing: 8, verticalSpacing: 22) {
      GridRow(alignment: .top) {
        emptyLabelCell
        ForEach(Self.providers) { provider in
          providerHeader(provider)
        }
      }

      GridRow {
        rowLabel("Model accuracy")
        ForEach(Self.providers) { provider in
          ratedCell(provider.accuracy)
        }
      }

      rowSeparator

      GridRow {
        rowLabel("Subscription requirements")
        ForEach(Self.providers) { provider in
          subscriptionCell(provider.subscription)
        }
      }

      rowSeparator

      GridRow {
        rowLabel("Ease of set up")
        ForEach(Self.providers) { provider in
          ratedCell(easeValue(for: provider))
        }
      }

      rowSeparator

      GridRow(alignment: .top) {
        rowLabel("Additional notes")
        ForEach(Self.providers) { provider in
          notesCell(provider.notes)
        }
      }

      GridRow {
        emptyLabelCell
        ForEach(Self.providers) { provider in
          selectButton(for: provider)
            .padding(.top, 14)
        }
      }
    }
    .frame(maxWidth: 1060)
  }

  private var emptyLabelCell: some View {
    Color.clear
      .gridCellUnsizedAxes([.horizontal, .vertical])
  }

  private var rowSeparator: some View {
    Rectangle()
      .fill(Color.black.opacity(0.15))
      .frame(height: 0.75)
  }

  private func rowLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 14))
      .fontWeight(.semibold)
      .foregroundColor(.black)
      .fixedSize(horizontal: false, vertical: true)
      .gridColumnAlignment(.leading)
  }

  private func providerHeader(_ provider: ComparisonProvider) -> some View {
    VStack(spacing: 7) {
      headerIcon(for: provider.id)
      Text(provider.title)
        .font(.system(size: 16))
        .fontWeight(.semibold)
        .foregroundColor(.black)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 14)
  }

  @ViewBuilder
  private func headerIcon(for id: String) -> some View {
    switch id {
    case "chatgpt_claude":
      HStack(spacing: 9) {
        iconCircle(imageName: "ChatGPTLogo")
        iconCircle(imageName: "ClaudeLogo")
      }
    case "gemini":
      iconCircle(imageName: "GeminiLogo")
    default:
      iconCircle(systemName: "laptopcomputer")
    }
  }

  private func iconCircle(imageName: String) -> some View {
    Image(imageName)
      .resizable()
      .renderingMode(.original)
      .interpolation(.high)
      .antialiased(true)
      .scaledToFit()
      .frame(width: 20, height: 20)
      .frame(width: 36, height: 36)
      .background(Color.white.opacity(0.3))
      .clipShape(Circle())
      .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  private func iconCircle(systemName: String) -> some View {
    Image(systemName: systemName)
      .font(.system(size: 14, weight: .medium))
      .foregroundColor(.black.opacity(0.8))
      .frame(width: 36, height: 36)
      .background(Color.white.opacity(0.3))
      .clipShape(Circle())
      .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
  }

  /// The ChatGPT/Claude column upgrades to green once a CLI is detected on this Mac.
  private func easeValue(for provider: ComparisonProvider) -> RatedValue {
    if provider.id == "chatgpt_claude", isChatCLIInstalled {
      return RatedValue(text: "CLI installed", rating: .best)
    }
    return provider.ease
  }

  private func ratedCell(_ value: RatedValue) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(value.rating.dotGradient)
        .frame(width: 10, height: 10)
      Text(value.text)
        .font(.system(size: 14))
        .foregroundColor(.black)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func subscriptionCell(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 14))
      .foregroundColor(.black)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: 170)
  }

  private func notesCell(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 12))
      .foregroundColor(.black)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: 180)
  }

  private func selectButton(for provider: ComparisonProvider) -> some View {
    PanopticonSurfaceButton(
      action: { onSelect(provider.selectionName) },
      content: {
        Text("Select")
          .font(.system(size: 14))
          .fontWeight(.semibold)
          .tracking(-0.14)
      },
      background: Theme.Palette.ink,
      foreground: .white,
      borderColor: .clear,
      cornerRadius: 8,
      horizontalPadding: 40,
      verticalPadding: 8,
      isFilledStyle: true
    )
  }
}
