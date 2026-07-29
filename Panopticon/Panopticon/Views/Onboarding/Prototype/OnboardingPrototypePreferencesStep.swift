//
//  OnboardingPrototypePreferencesStep.swift
//  Panopticon
//

import SwiftUI

// MARK: - Preferences Step

struct OnboardingPrototypePreferencesStep: View {
  let onContinue: (Bool) -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      VStack(spacing: 24) {
        Text("Do you have a paid ChatGPT or Claude account?")
          .font(.system(size: 20))
          .foregroundColor(Theme.Palette.ink2)
          .multilineTextAlignment(.center)

        HStack(spacing: 8) {
          ForEach(["Yes", "No"], id: \.self) { option in
            Button {
              onContinue(option == "Yes")
            } label: {
              Text(option)
                .font(.system(size: 16))
                .foregroundColor(Theme.Palette.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.4))
                .clipShape(Capsule())
                .overlay(
                  Capsule()
                    .stroke(Theme.Palette.line, lineWidth: 1)
                )
                .shadow(
                  color: Theme.Palette.ink3.opacity(0.15),
                  radius: 2, x: 0, y: 0
                )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
          }
        }
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
