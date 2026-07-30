//
//  UpdaterManager.swift
//  Panopticon
//
//  Minimal Sparkle wrapper. The feed (SUFeedURL in Info.plist) points at the
//  self-hosted MCP server's /appcast.xml, which is generated on the fly from
//  this repo's GitHub releases. Update integrity relies on Sparkle's Apple
//  code-signing validation: release builds are Developer ID signed, and
//  Sparkle accepts an update whose signing team matches the installed app's.
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
