//
//  DayScrubberFrames.swift
//  Panopticon
//
//  Loads a logical day's captures off the main thread and hands them to the
//  scrubber. Split from DayScrubberView so the view itself stays a pure
//  function of its input and can be previewed with a fixed set of frames.
//

import SwiftUI

struct DayScrubberFrames: View {
  @Binding var selectedDate: Date
  let onOpenSettings: () -> Void
  let onOpenDatePicker: () -> Void

  @State private var screenshots: [Screenshot] = []
  /// Cards for the same day, used for the centred title and for search.
  @State private var cards: [TimelineCard] = []
  @State private var bounds: (start: Date, end: Date)?
  @State private var isLoading = true
  /// Newest capture anywhere in the database, used to offer a jump when the
  /// selected day has nothing. Recording gaps are normal, so an empty day is
  /// not an error state and should not read like one.
  @State private var mostRecentCapture: Date?
  /// Bumped on every load so the scrubber rebuilds its model (and its frame
  /// cache) when the day changes rather than holding the previous day's state.
  @State private var generation = 0

  var body: some View {
    ZStack {
      if isLoading {
        ZStack {
          Theme.Palette.ink
          ProgressView().controlSize(.small)
        }
      } else if screenshots.isEmpty {
        emptyDay
      } else if let bounds {
        DayScrubberView(
          screenshots: screenshots,
          dayStart: bounds.start,
          dayEnd: bounds.end,
          cards: cards,
          initialDate: nil,
          onOpenSettings: onOpenSettings,
          onOpenDatePicker: onOpenDatePicker
        )
        .id(generation)
      }
    }
    .task(id: selectedDate) { await load() }
  }

  private var emptyDay: some View {
    ZStack {
      Theme.Palette.ink
      VStack(spacing: 8) {
        Image(systemName: "photo.on.rectangle.angled")
          .font(.system(size: 26, weight: .light))
          .foregroundColor(Theme.Palette.ink3)
        Text("No captures on this day")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(Theme.Palette.canvas)
        Text("Recording skips idle stretches and any apps you've blocked.")
          .font(.system(size: 12))
          .foregroundColor(Theme.Palette.ink3)

        if let jumpTarget {
          Button {
            selectedDate = timelineDisplayDate(from: jumpTarget)
          } label: {
            Text("Jump to \(Self.jumpFormatter.string(from: jumpTarget))")
              .font(.system(size: 12, weight: .medium))
              .padding(.horizontal, 11)
              .padding(.vertical, 6)
              .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                  .fill(Theme.Palette.accent)
              )
              .foregroundColor(Theme.Palette.onAccent)
          }
          .buttonStyle(.plain)
          .pointingHandCursor()
          .padding(.top, 4)
        }
      }
    }
  }

  private static let jumpFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM"
    return formatter
  }()

  /// Only worth offering when it would actually move the user somewhere else.
  private var jumpTarget: Date? {
    guard let mostRecentCapture else { return nil }
    let target = timelineDisplayDate(from: mostRecentCapture)
    guard !Calendar.current.isDate(target, inSameDayAs: timelineDisplayDate(from: selectedDate))
    else { return nil }
    return target
  }

  private func load() async {
    isLoading = true
    let day = selectedDate
    let loaded = await Task.detached(priority: .userInitiated) {
      () -> ([Screenshot], [TimelineCard], Date, Date, Date?) in
      let info = day.getDayInfoFor4AMBoundary()
      let store = StorageManager.shared
      let shots = store.fetchScreenshotsInTimeRange(
        startTs: Int(info.startOfDay.timeIntervalSince1970),
        endTs: Int(info.endOfDay.timeIntervalSince1970)
      )
      // The scrubber's nearest-capture search is a binary search, so the input
      // must be ordered even if the query's ordering ever changes.
      let sorted = shots.sorted { $0.capturedAt < $1.capturedAt }
      let cards = store.fetchTimelineCards(forDay: info.dayString)
      // Only needed for the empty state; skip the extra query otherwise.
      let newest = sorted.isEmpty ? store.mostRecentScreenshotDate() : nil
      return (sorted, cards, info.startOfDay, info.endOfDay, newest)
    }.value

    screenshots = loaded.0
    cards = loaded.1
    bounds = (loaded.2, loaded.3)
    mostRecentCapture = loaded.4
    generation += 1
    isLoading = false
  }
}
