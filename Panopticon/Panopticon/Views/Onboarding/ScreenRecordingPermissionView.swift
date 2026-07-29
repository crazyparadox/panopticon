//
//  ScreenRecordingPermissionView.swift
//  Panopticon
//
//  Screen recording permission request using idiomatic ScreenCaptureKit approach
//

import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI

struct ScreenRecordingPermissionView: View {
  var onBack: () -> Void
  var onNext: () -> Void

  @State private var permissionState: PermissionState = .notRequested
  @State private var isCheckingPermission = false
  @State private var initiatedFlow = false

  enum PermissionState {
    case notRequested
    case granted
    case needsAction  // requested or settings opened, awaiting quit & reopen / toggle
  }

  private let brownAccent = Theme.Palette.ink
  private let privacyTextColor = Theme.Palette.ink2

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      HStack(alignment: .top, spacing: 60) {
        // Left side — text and controls
        VStack(alignment: .leading, spacing: 10) {
          Text("Last step!")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(Theme.Palette.accent)

          Text("Permission")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(.black)

          Text("Panopticon can help understand your day.")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Theme.Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)

          // Privacy info box
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "shield.fill")
                .font(.system(size: 14))
                .foregroundColor(privacyTextColor)
              Text("Panopticon is built to be private and secure.")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(privacyTextColor)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(
              "Panopticon stores all recordings locally on your Mac, and can process everything privately on your device using local AI models."
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(privacyTextColor)

            Text("You are always in control — you can pause or turn off Panopticon whenever you like.")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(privacyTextColor)
          }
          .padding(16)
          .frame(maxWidth: 351, alignment: .leading)
          .background(Color.white.opacity(0.3))
          .cornerRadius(5)
          .overlay(
            RoundedRectangle(cornerRadius: 5)
              .stroke(Theme.Palette.accent.opacity(0.15), lineWidth: 1)
          )
          .shadow(
            color: Theme.Palette.accent.opacity(0.3), radius: 4, x: 0, y: 0)

          // State-based messaging
          Group {
            switch permissionState {
            case .notRequested:
              EmptyView()
            case .granted:
              Text("✓ Permission granted! Click Next to continue.")
                .font(.system(size: 14))
                .foregroundColor(.green)
            case .needsAction:
              Text("Turn on Screen Recording for Panopticon, then quit and reopen the app to finish.")
                .font(.system(size: 14))
                .foregroundColor(.orange)
            }
          }

          // Action buttons
          Group {
            switch permissionState {
            case .notRequested:
              Button(action: requestPermission) {
                HStack(spacing: 6) {
                  if isCheckingPermission {
                    ProgressView()
                      .scaleEffect(0.7)
                      .progressViewStyle(CircularProgressViewStyle())
                  }
                  Text(isCheckingPermission ? "Checking..." : "Open System Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(-0.48)
                    .foregroundColor(brownAccent)
                }
                .padding(12)
              }
              .buttonStyle(.plain)
              .background(
                LinearGradient(
                  stops: [
                    .init(
                      color: Theme.Palette.accentTint.opacity(0.7), location: 0.73),
                    .init(
                      color: Theme.Palette.inset.opacity(0), location: 0.99),
                  ],
                  startPoint: UnitPoint(x: 0.7, y: 1),
                  endPoint: UnitPoint(x: 0.3, y: 0)
                )
                .background(Color.white.opacity(0.69))
              )
              .cornerRadius(6)
              .overlay(
                RoundedRectangle(cornerRadius: 6)
                  .stroke(Theme.Palette.line, lineWidth: 1)
              )
              .disabled(isCheckingPermission)
            case .needsAction:
              HStack {
                Spacer(minLength: 0)

                HStack(spacing: 12) {
                  Button(action: openSystemSettings) {
                    Text("Open System Settings")
                      .font(.system(size: 12, weight: .semibold))
                      .tracking(-0.48)
                      .foregroundColor(brownAccent)
                      .padding(12)
                  }
                  .buttonStyle(.plain)
                  .background(
                    LinearGradient(
                      stops: [
                        .init(
                          color: Theme.Palette.accentTint.opacity(0.7),
                          location: 0.73
                        ),
                        .init(
                          color: Theme.Palette.inset.opacity(0),
                          location: 0.99),
                      ],
                      startPoint: UnitPoint(x: 0.7, y: 1),
                      endPoint: UnitPoint(x: 0.3, y: 0)
                    )
                    .background(Color.white.opacity(0.69))
                  )
                  .cornerRadius(6)
                  .overlay(
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(Theme.Palette.line, lineWidth: 1)
                  )

                  Button(action: quitAndReopen) {
                    Text("Quit & Reopen")
                      .font(.system(size: 12, weight: .semibold))
                      .tracking(-0.48)
                      .foregroundColor(brownAccent)
                      .padding(12)
                  }
                  .buttonStyle(.plain)
                  .background(Color.white.opacity(0.69))
                  .cornerRadius(6)
                  .overlay(
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(Theme.Palette.line, lineWidth: 1)
                  )
                }
              }
            case .granted:
              EmptyView()
            }
          }

          Spacer()
        }
        .frame(maxWidth: 374)

        Spacer()

        // Right side - image
        if let image = NSImage(named: "ScreenRecordingPermissions") {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 486)
            .background(Theme.Palette.surface)
            .cornerRadius(8)
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.Palette.inset, lineWidth: 1)
            )
            .shadow(
              color: Theme.Palette.accent.opacity(0.25), radius: 3, x: 0,
              y: 2)
        }
      }

      // Navigation buttons — bottom right
      HStack(spacing: 15) {
        PanopticonSurfaceButton(
          action: onBack,
          content: { Text("Back").font(.system(size: 12, weight: .medium)).tracking(-0.48) },
          background: .white,
          foreground: Theme.Palette.ink3,
          borderColor: Theme.Palette.ink3,
          cornerRadius: 4,
          horizontalPadding: 40,
          verticalPadding: 12,
          isOutlinedStyle: true
        )
        PanopticonSurfaceButton(
          action: {
            if permissionState == .granted { onNext() }
          },
          content: { Text("Next").font(.system(size: 12, weight: .medium)).tracking(-0.48) },
          background: permissionState == .granted
            ? Theme.Palette.ink
            : Theme.Palette.ink.opacity(0.3),
          foreground: .white,
          borderColor: .clear,
          cornerRadius: 4,
          horizontalPadding: 40,
          verticalPadding: 12,
          isFilledStyle: permissionState == .granted
        )
        .disabled(permissionState != .granted)
      }
    }
    .padding(.leading, 105)
    .padding(.trailing, 60)
    .padding(.top, 30)
    .padding(.bottom, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      // If already granted, mark as granted; otherwise start in notRequested
      if CGPreflightScreenCaptureAccess() {
        permissionState = .granted
        Task { @MainActor in AppDelegate.allowTermination = false }
      } else {
        permissionState = .notRequested
        Task { @MainActor in AppDelegate.allowTermination = true }
      }
    }
    // Re-check when app becomes active again (e.g., returning from System Settings)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      // Only transition to granted here; avoid flipping notChecked to denied automatically
      if CGPreflightScreenCaptureAccess() {
        permissionState = .granted
        Task { @MainActor in AppDelegate.allowTermination = false }
      }
    }
    .onDisappear {
      Task { @MainActor in AppDelegate.allowTermination = false }
    }
  }

  private func requestPermission() {
    guard !isCheckingPermission else { return }
    isCheckingPermission = true
    initiatedFlow = true

    // This will prompt and register the app with TCC; may return false
    _ = CGRequestScreenCaptureAccess()
    if CGPreflightScreenCaptureAccess() {
      permissionState = .granted
      Task { @MainActor in AppDelegate.allowTermination = false }
    } else {
      permissionState = .needsAction
      Task { @MainActor in AppDelegate.allowTermination = true }
    }
    isCheckingPermission = false
  }

  private func openSystemSettings() {
    initiatedFlow = true
    Task { @MainActor in AppDelegate.allowTermination = true }
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      _ = NSWorkspace.shared.open(url)
    }
    // Move to needsAction so we show Quit & Reopen guidance
    if permissionState != .granted { permissionState = .needsAction }
  }

  private func quitAndReopen() {
    Task { @MainActor in
      AppDelegate.allowTermination = true
      NSApp.terminate(nil)
    }
  }
}
