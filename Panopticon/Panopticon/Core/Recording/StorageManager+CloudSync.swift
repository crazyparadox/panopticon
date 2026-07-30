//
//  StorageManager+CloudSync.swift
//  Panopticon
//
//  Read-side queries for cloud sync. Sync pushes day snapshots, so these
//  return raw unix timestamps (which TimelineCard doesn't carry) plus the
//  metadata JSON verbatim — the server stores it as-is.
//

import Foundation
import GRDB

/// One timeline card in the wire shape the sync endpoint expects.
struct SyncCard: Codable {
  let day: String
  let startTs: Int
  let endTs: Int
  let startTime: String
  let endTime: String
  let category: String
  let subcategory: String
  let title: String
  let summary: String
  let detailedSummary: String
  let distractions: [Distraction]?
  let appSites: AppSites?
}

extension StorageManager {
  /// Every logical day that has at least one live timeline card, newest first.
  func fetchTimelineDays(limit: Int = 400) -> [String] {
    (try? timedRead("fetchTimelineDays") { db in
      try String.fetchAll(
        db,
        sql: """
              SELECT DISTINCT day FROM timeline_cards
              WHERE is_deleted = 0
              ORDER BY day DESC
              LIMIT ?
          """, arguments: [limit])
    }) ?? []
  }

  /// A day's cards in sync wire shape (raw timestamps included).
  func fetchSyncCards(forDay day: String) -> [SyncCard] {
    let decoder = JSONDecoder()
    return
      (try? timedRead("fetchSyncCards(\(day))") { db in
        try Row.fetchAll(
          db,
          sql: """
                SELECT day, start_ts, end_ts, start, end, category, subcategory,
                       title, summary, detailed_summary, metadata
                FROM timeline_cards
                WHERE day = ? AND is_deleted = 0
                ORDER BY start_ts ASC
            """, arguments: [day]
        )
        .map { row in
          var distractions: [Distraction]? = nil
          var appSites: AppSites? = nil
          if let metadataString: String = row["metadata"],
            let jsonData = metadataString.data(using: .utf8)
          {
            if let meta = try? decoder.decode(TimelineMetadata.self, from: jsonData) {
              distractions = meta.distractions
              appSites = meta.appSites
            } else if let legacy = try? decoder.decode([Distraction].self, from: jsonData) {
              distractions = legacy
            }
          }
          return SyncCard(
            day: row["day"],
            startTs: row["start_ts"],
            endTs: row["end_ts"],
            startTime: row["start"] ?? "",
            endTime: row["end"] ?? "",
            category: row["category"],
            subcategory: row["subcategory"] ?? "",
            title: row["title"],
            summary: row["summary"],
            detailedSummary: row["detailed_summary"] ?? "",
            distractions: distractions,
            appSites: appSites
          )
        }
      }) ?? []
  }
}
