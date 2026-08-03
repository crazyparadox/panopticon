//
//  TimelineDataModels.swift
//  Panopticon
//
//  Data models for the new UI timeline components
//

import Foundation
import SwiftUI

/// Represents an activity in the timeline view
struct TimelineActivity: Identifiable {
  let id: String
  let recordId: Int64?
  let batchId: Int64?  // Tracks source batch for retry functionality
  let startTime: Date
  let endTime: Date
  let title: String
  let summary: String
  let detailedSummary: String
  let category: String
  let subcategory: String
  let distractions: [Distraction]?
  let videoSummaryURL: String?
  let screenshot: NSImage?
  let appSites: AppSites?
  let isBackupGenerated: Bool?

  static func stableId(
    recordId: Int64?, batchId: Int64?, startTime: Date, endTime: Date, title: String,
    category: String, subcategory: String
  ) -> String {
    if let recordId {
      return "record:\(recordId)"
    }
    let batchPart = batchId.map { "batch:\($0)" } ?? "batch:unknown"
    let startMs = Int64((startTime.timeIntervalSince1970 * 1000).rounded())
    let endMs = Int64((endTime.timeIntervalSince1970 * 1000).rounded())
    let contentHash = stableHash("\(title)|\(category)|\(subcategory)")
    return "\(batchPart)-\(startMs)-\(endMs)-\(contentHash)"
  }

  private static func stableHash(_ input: String) -> String {
    var hash: UInt64 = 5381
    for byte in input.utf8 {
      hash = ((hash << 5) &+ hash) &+ UInt64(byte)
    }
    return String(hash, radix: 36)
  }

  func withCategory(_ newCategory: String) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: recordId,
      batchId: batchId,
      startTime: startTime,
      endTime: endTime,
      title: title,
      summary: summary,
      detailedSummary: detailedSummary,
      category: newCategory,
      subcategory: subcategory,
      distractions: distractions,
      videoSummaryURL: videoSummaryURL,
      screenshot: screenshot,
      appSites: appSites,
      isBackupGenerated: isBackupGenerated
    )
  }

  func withVideoSummaryURL(_ newVideoSummaryURL: String?) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: recordId,
      batchId: batchId,
      startTime: startTime,
      endTime: endTime,
      title: title,
      summary: summary,
      detailedSummary: detailedSummary,
      category: category,
      subcategory: subcategory,
      distractions: distractions,
      videoSummaryURL: newVideoSummaryURL,
      screenshot: screenshot,
      appSites: appSites,
      isBackupGenerated: isBackupGenerated
    )
  }
}

/// Sheet view for selecting a date
/// Compact month picker in the app's own idiom. Replaces a stock graphical
/// DatePicker, which came from upstream and matched neither the palette nor the
/// scale of the rest of the UI.
struct DatePickerSheet: View {
  @Binding var selectedDate: Date
  @Binding var isPresented: Bool

  /// Month currently on screen, which the chevrons move independently of the
  /// selection so you can look around without changing the day.
  @State private var visibleMonth: Date = Date()

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2  // Monday, matching the rest of the timeline
    return calendar
  }()

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    return formatter
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      weekdayRow
      monthGrid
      footer
    }
    .padding(18)
    .frame(width: 296)
    .background(Theme.Palette.surface)
    .onAppear { visibleMonth = selectedDate }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 0) {
      Text(Self.monthFormatter.string(from: visibleMonth))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(Theme.Palette.ink)
      Spacer(minLength: 8)
      monthStepButton(systemName: "chevron.left", delta: -1, enabled: true)
      monthStepButton(systemName: "chevron.right", delta: 1, enabled: canStepForward)
    }
  }

  /// Forward navigation stops at the current month: there is nothing recorded in
  /// the future.
  private var canStepForward: Bool {
    guard
      let next = Self.calendar.date(byAdding: .month, value: 1, to: startOfMonth(visibleMonth))
    else { return false }
    return next <= startOfMonth(Date())
  }

  private func monthStepButton(systemName: String, delta: Int, enabled: Bool) -> some View {
    Button {
      if let moved = Self.calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
        visibleMonth = moved
      }
    } label: {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(enabled ? Theme.Palette.ink2 : Theme.Palette.ink3.opacity(0.4))
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .disabled(!enabled)
  }

  // MARK: - Grid

  private var weekdayRow: some View {
    HStack(spacing: 0) {
      ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
        Text(symbol)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(Theme.Palette.ink3)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var orderedWeekdaySymbols: [String] {
    // veryShortWeekdaySymbols starts at Sunday; rotate to the calendar's own
    // first weekday so the columns line up with the grid below.
    let symbols = Self.calendar.veryShortWeekdaySymbols
    let shift = Self.calendar.firstWeekday - 1
    return Array(symbols[shift...] + symbols[..<shift])
  }

  private var monthGrid: some View {
    let days = daysForVisibleMonth()
    return VStack(spacing: 2) {
      ForEach(Array(stride(from: 0, to: days.count, by: 7)), id: \.self) { rowStart in
        HStack(spacing: 2) {
          ForEach(rowStart..<min(rowStart + 7, days.count), id: \.self) { index in
            dayCell(days[index])
          }
        }
      }
    }
  }

  @ViewBuilder
  private func dayCell(_ day: Date?) -> some View {
    if let day {
      let isSelected = Self.calendar.isDate(day, inSameDayAs: selectedDate)
      let isToday = Self.calendar.isDateInToday(day)
      let isFuture = day > Date()

      Button {
        selectedDate = day
        isPresented = false
      } label: {
        Text("\(Self.calendar.component(.day, from: day))")
          .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
          .foregroundColor(dayColor(isSelected: isSelected, isToday: isToday, isFuture: isFuture))
          .frame(maxWidth: .infinity)
          .frame(height: 30)
          .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
              .fill(isSelected ? Theme.Palette.accent : Color.clear)
          )
          .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
              .stroke(
                isToday && !isSelected ? Theme.Palette.accent.opacity(0.45) : Color.clear,
                lineWidth: 1)
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .disabled(isFuture)
    } else {
      // Leading and trailing blanks that pad the month into whole weeks.
      Color.clear.frame(maxWidth: .infinity).frame(height: 30)
    }
  }

  private func dayColor(isSelected: Bool, isToday: Bool, isFuture: Bool) -> Color {
    if isSelected { return Theme.Palette.onAccent }
    if isFuture { return Theme.Palette.ink3.opacity(0.4) }
    if isToday { return Theme.Palette.accent }
    return Theme.Palette.ink
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 8) {
      Button {
        selectedDate = Date()
        isPresented = false
      } label: {
        Text("Today")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(Theme.Palette.ink)
          .padding(.horizontal, 11)
          .padding(.vertical, 6)
          .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
              .fill(Theme.Palette.inset)
          )
      }
      .buttonStyle(.plain)
      .pointingHandCursor()

      Spacer()

      Button { isPresented = false } label: {
        Text("Close")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(Theme.Palette.ink2)
          .padding(.horizontal, 11)
          .padding(.vertical, 6)
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .keyboardShortcut(.escape, modifiers: [])
    }
  }

  // MARK: - Layout maths

  private func startOfMonth(_ date: Date) -> Date {
    Self.calendar.date(
      from: Self.calendar.dateComponents([.year, .month], from: date)) ?? date
  }

  /// The visible month padded with nils so it starts on the calendar's first
  /// weekday and fills whole rows.
  private func daysForVisibleMonth() -> [Date?] {
    let first = startOfMonth(visibleMonth)
    guard let range = Self.calendar.range(of: .day, in: .month, for: first) else { return [] }

    let weekday = Self.calendar.component(.weekday, from: first)
    let leading = (weekday - Self.calendar.firstWeekday + 7) % 7

    var cells: [Date?] = Array(repeating: nil, count: leading)
    for offset in 0..<range.count {
      cells.append(Self.calendar.date(byAdding: .day, value: offset, to: first))
    }
    while cells.count % 7 != 0 { cells.append(nil) }
    return cells
  }
}
