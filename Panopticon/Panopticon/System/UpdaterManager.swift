//
//  UpdaterManager.swift
//  Panopticon
//
//  Minimal Sparkle wrapper. The feed (SUFeedURL in Info.plist) is served by
//  Amore, which hosts the release archives and signs them with the EdDSA key
//  whose public half is SUPublicEDKey. Sparkle rejects any update that isn't
//  signed with that key, on top of its Developer ID code-signing check.
//

import Sparkle
import SwiftUI

@MainActor
final class UpdaterManager: ObservableObject {
  static let shared = UpdaterManager()

  private let controller: SPUStandardUpdaterController

  @Published var canCheckForUpdates = false

  private init() {
    // startingUpdater: true begins the scheduled background check cycle.
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    controller.updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
