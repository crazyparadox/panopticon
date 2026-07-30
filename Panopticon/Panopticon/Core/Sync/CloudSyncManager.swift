//
//  CloudSyncManager.swift
//  Panopticon
//
//  Pushes the local timeline to the hosted sync endpoint (see mcp/ in the
//  repo: a Vercel function in front of Neon Postgres). Agents then read the
//  data back over MCP.
//
//  Sync model: DAY SNAPSHOTS. The analysis pipeline regenerates a day's cards
//  in place, so the server replaces whole days; re-pushing is idempotent.
//  Every cycle pushes the trailing few days (the sliding-window regeneration
//  only touches recent history); enabling sync the first time backfills every
//  recorded day.
//

import Foundation

enum CloudSyncPreferences {
  private static let enabledKey = "cloudSyncEnabled"
  private static let endpointKey = "cloudSyncEndpoint"
  private static let deviceIdKey = "cloudSyncDeviceId"
  private static let didBackfillKey = "cloudSyncDidBackfill"
  private static let lastSyncKey = "cloudSyncLastSyncedAt"
  /// KeychainManager slot for the bearer token.
  static let tokenKeychainKey = "cloudSyncToken"

  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: enabledKey) }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  /// Base URL of the deployment, e.g. "https://panopticon-mcp.vercel.app".
  static var endpoint: String {
    get { UserDefaults.standard.string(forKey: endpointKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: endpointKey) }
  }

  static var token: String {
    get { KeychainManager.shared.retrieve(for: tokenKeychainKey) ?? "" }
    set { _ = KeychainManager.shared.store(newValue, for: tokenKeychainKey) }
  }

  static var deviceId: String {
    if let existing = UserDefaults.standard.string(forKey: deviceIdKey) { return existing }
    let generated = "mac-" + UUID().uuidString.lowercased()
    UserDefaults.standard.set(generated, forKey: deviceIdKey)
    return generated
  }

  static var didBackfill: Bool {
    get { UserDefaults.standard.bool(forKey: didBackfillKey) }
    set { UserDefaults.standard.set(newValue, forKey: didBackfillKey) }
  }

  static var lastSyncedAt: Date? {
    get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
    set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
  }
}

@MainActor
final class CloudSyncManager: ObservableObject {
  static let shared = CloudSyncManager()

  enum Status: Equatable {
    case idle
    case syncing
    case failed(String)
  }

  @Published private(set) var status: Status = .idle
  @Published private(set) var lastSyncedAt: Date? = CloudSyncPreferences.lastSyncedAt

  /// Days pushed on every routine cycle (regeneration only touches recent
  /// history, so the trailing window covers all mutations).
  private static let trailingDayCount = 3
  /// Routine cadence: every 3.5 hours. The agent-facing copy doesn't need to
  /// be real-time — it needs to be recent — and each cycle re-pushes the
  /// trailing days, so anything analyzed since the last cycle is included.
  private let cycleInterval: TimeInterval = 3.5 * 60 * 60

  private var timer: Timer?
  private var syncTask: Task<Void, Never>?
  private var pendingDebounce: Task<Void, Never>?

  private init() {}

  func start() {
    guard timer == nil else { return }

    timer = Timer.scheduledTimer(withTimeInterval: cycleInterval, repeats: true) { _ in
      Task { @MainActor in CloudSyncManager.shared.syncSoon() }
    }

    // One push shortly after launch so the cloud copy is fresh when the app
    // comes back from a long sleep, then the 3.5h cycle takes over. (No
    // per-batch trigger — the requested cadence is every few hours.)
    syncSoon(after: 30)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    pendingDebounce?.cancel()
    syncTask?.cancel()
  }

  /// Schedule a sync shortly, collapsing bursts into one run.
  func syncSoon(after delay: TimeInterval = 1) {
    guard CloudSyncPreferences.isEnabled else { return }
    pendingDebounce?.cancel()
    pendingDebounce = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.syncNow()
    }
  }

  /// Run a sync immediately (also what the Settings "Sync now" button calls).
  func syncNow() {
    guard CloudSyncPreferences.isEnabled else { return }
    guard syncTask == nil else { return }

    let endpoint = CloudSyncPreferences.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let token = CloudSyncPreferences.token
    guard let baseURL = URL(string: endpoint), !token.isEmpty else {
      status = .failed("Sync endpoint or token not configured")
      return
    }

    status = .syncing
    syncTask = Task { [weak self] in
      defer { self?.syncTask = nil }
      do {
        try await Self.performSync(baseURL: baseURL, token: token)
        await MainActor.run {
          let now = Date()
          CloudSyncPreferences.lastSyncedAt = now
          self?.lastSyncedAt = now
          self?.status = .idle
        }
      } catch is CancellationError {
        await MainActor.run { self?.status = .idle }
      } catch {
        print("[CloudSync] sync failed: \(error.localizedDescription)")
        await MainActor.run { self?.status = .failed(error.localizedDescription) }
      }
    }
  }

  // MARK: - Transport

  private struct DaysPayload: Codable {
    struct Day: Codable {
      let day: String
      let cards: [SyncCard]
    }
    let deviceId: String
    let days: [Day]
  }

  private struct RecapsPayload: Codable {
    struct Recap: Codable {
      let day: String
      let payload: AnyJSON
    }
    let deviceId: String
    let recaps: [Recap]
  }

  private static func performSync(baseURL: URL, token: String) async throws {
    let deviceId = CloudSyncPreferences.deviceId

    // Which days to push: trailing window, or everything on first sync.
    let allDays = await detachedFetch { StorageManager.shared.fetchTimelineDays() }
    let days: [String]
    if CloudSyncPreferences.didBackfill {
      days = Array(allDays.prefix(trailingDayCount))
    } else {
      days = allDays
    }
    guard !days.isEmpty else { return }

    // Push cards in batches of days so one request stays well under limits.
    for chunk in days.chunked(into: 14) {
      var payloadDays: [DaysPayload.Day] = []
      for day in chunk {
        let cards = await detachedFetch { StorageManager.shared.fetchSyncCards(forDay: day) }
        payloadDays.append(DaysPayload.Day(day: day, cards: cards))
      }
      try await post(
        to: baseURL.appendingPathComponent("sync/days"),
        token: token,
        body: DaysPayload(deviceId: deviceId, days: payloadDays)
      )
      try Task.checkCancellation()
    }

    // Recaps: the payloads are small; push all of them every time.
    let standups = await detachedFetch { StorageManager.shared.fetchAllDailyStandups() }
    if !standups.isEmpty {
      let recaps = standups.compactMap { entry -> RecapsPayload.Recap? in
        guard let data = entry.payloadJSON.data(using: .utf8),
          let value = try? JSONDecoder().decode(AnyJSON.self, from: data)
        else { return nil }
        return RecapsPayload.Recap(day: entry.standupDay, payload: value)
      }
      for chunk in recaps.chunked(into: 60) {
        try await post(
          to: baseURL.appendingPathComponent("sync/recaps"),
          token: token,
          body: RecapsPayload(deviceId: deviceId, recaps: chunk)
        )
      }
    }

    await MainActor.run { CloudSyncPreferences.didBackfill = true }
  }

  private static func post<T: Encodable>(to url: URL, token: String, body: T) async throws {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(body)
    request.timeoutInterval = 60

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw NSError(
        domain: "CloudSync", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No HTTP response from sync endpoint"])
    }
    guard (200..<300).contains(http.statusCode) else {
      let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? ""
      throw NSError(
        domain: "CloudSync", code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "Sync endpoint returned \(http.statusCode): \(bodyPreview)"])
    }
  }

  private static func detachedFetch<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await Task.detached(priority: .utility) { work() }.value
  }
}

// MARK: - Helpers

/// Minimal JSON passthrough so recap payload blobs re-encode verbatim.
enum AnyJSON: Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([AnyJSON])
  case object([String: AnyJSON])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let b = try? container.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? container.decode(Double.self) {
      self = .number(n)
    } else if let s = try? container.decode(String.self) {
      self = .string(s)
    } else if let a = try? container.decode([AnyJSON].self) {
      self = .array(a)
    } else {
      self = .object(try container.decode([String: AnyJSON].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let b): try container.encode(b)
    case .number(let n): try container.encode(n)
    case .string(let s): try container.encode(s)
    case .array(let a): try container.encode(a)
    case .object(let o): try container.encode(o)
    }
  }
}

extension Array {
  fileprivate func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}
