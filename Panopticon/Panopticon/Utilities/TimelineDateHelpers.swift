//
//  TimelineDateHelpers.swift
//  Panopticon
//
//  Shared date helpers for the 4 AM logical-day boundary, plus a small
//  conditional-modifier convenience. These outlived the timeline UI because
//  settings-side export still reasons about display days.
//

import SwiftUI

/// Normalizes a date to midday so day-granularity comparisons are immune to
/// DST shifts and timezone edges.
func normalizedTimelineDate(_ date: Date) -> Date {
  let calendar = Calendar.current
  if let normalized = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) {
    return normalized
  }
  let startOfDay = calendar.startOfDay(for: date)
  return calendar.date(byAdding: DateComponents(hour: 12), to: startOfDay) ?? date
}

/// The logical day a date belongs to, where a day runs 4 AM → 4 AM.
func timelineDisplayDate(from date: Date, now: Date = Date()) -> Date {
  let calendar = Calendar.current
  var normalizedDate = normalizedTimelineDate(date)
  let normalizedNow = normalizedTimelineDate(now)
  let nowHour = calendar.component(.hour, from: now)

  if nowHour < 4 && calendar.isDate(normalizedDate, inSameDayAs: normalizedNow) {
    normalizedDate = calendar.date(byAdding: .day, value: -1, to: normalizedDate) ?? normalizedDate
  }

  return normalizedDate
}

extension View {
  @ViewBuilder
  func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
