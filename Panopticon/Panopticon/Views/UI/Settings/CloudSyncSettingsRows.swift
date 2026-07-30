//
//  CloudSyncSettingsRows.swift
//  Panopticon
//
//  Settings rows for the cloud sync section: endpoint + token, an enable
//  toggle, and a manual "Sync now" with status. See mcp/README.md in the repo
//  for the server-side setup (Vercel + Neon).
//

import SwiftUI

struct CloudSyncSettingsRows: View {
  @ObservedObject private var syncManager = CloudSyncManager.shared

  @State private var isEnabled = CloudSyncPreferences.isEnabled
  @State private var endpoint = CloudSyncPreferences.endpoint
  @State private var token = CloudSyncPreferences.token

  private var configurationValid: Bool {
    URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.hasPrefix("http")
      == true && !token.isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(
        label: "Sync to cloud",
        subtitle: "Pushes the last few days every 3\u{2013}4 hours so your agents stay current."
      ) {
        SettingsToggle(
          isOn: Binding(
            get: { isEnabled },
            set: { newValue in
              isEnabled = newValue
              CloudSyncPreferences.isEnabled = newValue
              if newValue { CloudSyncManager.shared.syncSoon() }
            }
          )
        )
      }

      SettingsRow(
        label: "Endpoint",
        subtitle: "Your deployment URL, e.g. https://panopticon-mcp.vercel.app"
      ) {
        TextField("https://…", text: $endpoint)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 12))
          .frame(width: 280)
          .onChange(of: endpoint) { _, newValue in
            CloudSyncPreferences.endpoint = newValue
          }
      }

      SettingsRow(
        label: "Token",
        subtitle: "The PANOPTICON_TOKEN from your deployment. Stored in the Keychain."
      ) {
        SecureField("Bearer token", text: $token)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 12))
          .frame(width: 280)
          .onChange(of: token) { _, newValue in
            CloudSyncPreferences.token = newValue
          }
      }

      SettingsRow(label: "Status", subtitle: statusSubtitle, showsDivider: false) {
        SettingsSecondaryButton(
          title: syncManager.status == .syncing ? "Syncing…" : "Sync now",
          isDisabled: !isEnabled || !configurationValid || syncManager.status == .syncing
        ) {
          CloudSyncManager.shared.syncNow()
        }
      }
    }
  }

  private var statusSubtitle: String {
    switch syncManager.status {
    case .syncing:
      return "Pushing days to the endpoint…"
    case .failed(let message):
      return "Last sync failed: \(message)"
    case .idle:
      if let last = syncManager.lastSyncedAt {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last synced \(formatter.localizedString(for: last, relativeTo: Date()))"
      }
      return "Not synced yet"
    }
  }
}
