//
//  DayScrubberModel.swift
//  Panopticon
//
//  Backing state for the day scrubber: which capture is on screen, the sessions
//  the day breaks into, the zoom window over the track, and playback.
//
//  Captures are irregularly spaced (idle stretches are skipped entirely), so the
//  track maps *wall-clock position* to the nearest capture rather than treating
//  the day as an evenly sampled strip.
//

import AppKit
import Foundation
import SwiftUI

/// A run of captures with no long gap inside it. These are the filled segments
/// on the track; the space between them is time that was never recorded.
struct CaptureSession: Identifiable, Equatable {
  let id: Int
  let startIndex: Int
  let endIndex: Int
  let start: Date
  let end: Date

  var frameCount: Int { endIndex - startIndex + 1 }
}

@MainActor
final class DayScrubberModel: ObservableObject {
  @Published private(set) var currentImage: CGImage?
  @Published private(set) var index: Int = 0
  @Published private(set) var isLoading: Bool = false
  @Published var isPlaying: Bool = false
  /// Width of the visible slice of the day on the track, in seconds.
  @Published private(set) var visibleSpan: TimeInterval
  /// Left edge of the visible window. Stored rather than derived from the
  /// playhead: a window that recentres on every seek would slide the playhead
  /// back under the cursor mid-drag, so it only moves when the playhead would
  /// otherwise leave the track.
  @Published private(set) var windowStart: Date

  let screenshots: [Screenshot]
  let dayStart: Date
  let dayEnd: Date
  let sessions: [CaptureSession]

  /// A gap longer than this ends a session. Captures land roughly every 10s, so
  /// five minutes of silence is unambiguously a break rather than jitter.
  private static let sessionGapThreshold: TimeInterval = 300

  /// Opening window width. Zoomed in enough that individual sessions are
  /// distinguishable and clickable, with the fit control there to pull back.
  static let defaultVisibleSpan: TimeInterval = 3600

  private let loader: ScreenshotSlideshowFrameLoader
  private var requestID = 0
  private var playbackTimer: Timer?

  init(screenshots: [Screenshot], dayStart: Date, dayEnd: Date, maxRenderHeight: Int = 1100) {
    self.screenshots = screenshots
    self.dayStart = dayStart
    self.dayEnd = dayEnd
    let span = max(1, dayEnd.timeIntervalSince(dayStart))
    let visible = min(Self.defaultVisibleSpan, span)
    self.visibleSpan = visible
    // Open on the tail of the day, where the most recent captures are.
    let anchor = screenshots.last?.capturedDate ?? dayStart
    self.windowStart = Self.clampWindowStart(
      anchor.addingTimeInterval(-visible / 2),
      visibleSpan: visible, dayStart: dayStart, dayEnd: dayEnd)
    self.loader = ScreenshotSlideshowFrameLoader(
      screenshots: screenshots, maxRenderHeight: maxRenderHeight)
    self.sessions = Self.buildSessions(from: screenshots)
  }

  deinit { playbackTimer?.invalidate() }

  static func buildSessions(from screenshots: [Screenshot]) -> [CaptureSession] {
    guard !screenshots.isEmpty else { return [] }
    var result: [CaptureSession] = []
    var runStart = 0
    for i in 1..<screenshots.count {
      let gap = TimeInterval(screenshots[i].capturedAt - screenshots[i - 1].capturedAt)
      if gap > sessionGapThreshold {
        result.append(
          CaptureSession(
            id: result.count, startIndex: runStart, endIndex: i - 1,
            start: screenshots[runStart].capturedDate,
            end: screenshots[i - 1].capturedDate))
        runStart = i
      }
    }
    result.append(
      CaptureSession(
        id: result.count, startIndex: runStart, endIndex: screenshots.count - 1,
        start: screenshots[runStart].capturedDate,
        end: screenshots[screenshots.count - 1].capturedDate))
    return result
  }

  var isEmpty: Bool { screenshots.isEmpty }

  var currentScreenshot: Screenshot? {
    screenshots.indices.contains(index) ? screenshots[index] : nil
  }

  var currentDate: Date? { currentScreenshot?.capturedDate }

  var daySpan: TimeInterval { max(1, dayEnd.timeIntervalSince(dayStart)) }

  /// Session containing the playhead, used to label the view and to decide what
  /// the play button acts on.
  var currentSession: CaptureSession? {
    sessions.first { index >= $0.startIndex && index <= $0.endIndex }
  }

  // MARK: - Track geometry

  static func clampWindowStart(
    _ proposed: Date, visibleSpan: TimeInterval, dayStart: Date, dayEnd: Date
  ) -> Date {
    let earliest = dayStart.timeIntervalSince1970
    let latest = max(earliest, dayEnd.timeIntervalSince1970 - visibleSpan)
    return Date(timeIntervalSince1970: min(max(proposed.timeIntervalSince1970, earliest), latest))
  }

  var windowEnd: Date { windowStart.addingTimeInterval(visibleSpan) }

  /// Slide the window only when the playhead has left it, keeping a small
  /// margin so stepping near an edge scrolls before the marker is clipped.
  private func ensurePlayheadVisible() {
    guard let now = currentDate else { return }
    let margin = visibleSpan * 0.08
    let lower = windowStart.addingTimeInterval(margin)
    let upper = windowEnd.addingTimeInterval(-margin)
    guard now < lower || now > upper else { return }
    windowStart = Self.clampWindowStart(
      now.addingTimeInterval(-visibleSpan / 2),
      visibleSpan: visibleSpan, dayStart: dayStart, dayEnd: dayEnd)
  }

  /// Re-anchor the window around the playhead after a zoom change.
  private func recentreWindow() {
    let anchor = currentDate ?? windowStart.addingTimeInterval(visibleSpan / 2)
    windowStart = Self.clampWindowStart(
      anchor.addingTimeInterval(-visibleSpan / 2),
      visibleSpan: visibleSpan, dayStart: dayStart, dayEnd: dayEnd)
  }

  /// Position of an instant within the visible window, 0...1. Values outside
  /// that range mean the instant is scrolled off the track.
  func fraction(of date: Date) -> Double {
    date.timeIntervalSince(windowStart) / visibleSpan
  }

  func fraction(of screenshot: Screenshot) -> Double {
    fraction(of: screenshot.capturedDate)
  }

  var currentFraction: Double {
    guard let date = currentDate else { return 0 }
    return fraction(of: date)
  }

  func date(atFraction fraction: Double) -> Date {
    windowStart.addingTimeInterval(min(1, max(0, fraction)) * visibleSpan)
  }

  // MARK: - Zoom

  private static let zoomSteps: [TimeInterval] = [
    15 * 60, 30 * 60, 60 * 60, 3 * 3600, 6 * 3600, 12 * 3600, 24 * 3600,
  ]

  var canZoomIn: Bool { visibleSpan > Self.zoomSteps.first! }
  var canZoomOut: Bool { visibleSpan < min(daySpan, Self.zoomSteps.last!) }

  func zoomIn() {
    guard let next = Self.zoomSteps.last(where: { $0 < visibleSpan }) else { return }
    visibleSpan = next
    recentreWindow()
  }

  func zoomOut() {
    guard let next = Self.zoomSteps.first(where: { $0 > visibleSpan }) else { return }
    visibleSpan = min(next, daySpan)
    recentreWindow()
  }

  /// Frame the whole day, the "fit" control.
  func zoomToFit() {
    visibleSpan = daySpan
    windowStart = dayStart
  }

  // MARK: - Navigation

  func seek(toFraction fraction: Double) {
    guard !screenshots.isEmpty else { return }
    setIndex(nearestIndex(to: date(atFraction: fraction)))
  }

  func step(by delta: Int) {
    guard !screenshots.isEmpty else { return }
    setIndex(index + delta)
  }

  func jumpToStart() { setIndex(0) }
  func jumpToEnd() { setIndex(max(0, screenshots.count - 1)) }

  func seek(to date: Date) {
    guard !screenshots.isEmpty else { return }
    setIndex(nearestIndex(to: date))
  }

  func jump(to session: CaptureSession) { setIndex(session.startIndex) }

  /// Move to the neighbouring session, so the chevrons skip idle time instead of
  /// crawling through it one capture at a time.
  func goToAdjacentSession(forward: Bool) {
    guard let current = currentSession else { return }
    let target = forward ? current.id + 1 : current.id - 1
    guard sessions.indices.contains(target) else {
      setIndex(forward ? screenshots.count - 1 : 0)
      return
    }
    setIndex(sessions[target].startIndex)
  }

  private func nearestIndex(to target: Date) -> Int {
    let ts = Int(target.timeIntervalSince1970)
    var low = 0
    var high = screenshots.count - 1
    while low < high {
      let mid = (low + high) / 2
      if screenshots[mid].capturedAt < ts {
        low = mid + 1
      } else {
        high = mid
      }
    }
    // `low` is the first capture at or after the target; the one before it may
    // be closer in time.
    if low > 0 {
      let after = screenshots[low].capturedAt
      let before = screenshots[low - 1].capturedAt
      if abs(before - ts) <= abs(after - ts) { return low - 1 }
    }
    return low
  }

  private func setIndex(_ raw: Int) {
    let clamped = min(max(0, raw), max(0, screenshots.count - 1))
    guard clamped != index || currentImage == nil else { return }
    index = clamped
    ensurePlayheadVisible()
    loadFrame(at: clamped)
  }

  // MARK: - Playback

  func togglePlayback() {
    isPlaying ? stopPlayback() : startPlayback()
  }

  func startPlayback() {
    guard !screenshots.isEmpty else { return }
    // Restart from the top of the day once the end is reached, so pressing play
    // on a finished timeline does something visible.
    if index >= screenshots.count - 1 { setIndex(0) }
    isPlaying = true
    playbackTimer?.invalidate()
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.advanceForPlayback() }
    }
  }

  func stopPlayback() {
    isPlaying = false
    playbackTimer?.invalidate()
    playbackTimer = nil
  }

  private func advanceForPlayback() {
    guard isPlaying else { return }
    guard index < screenshots.count - 1 else {
      stopPlayback()
      return
    }
    setIndex(index + 1)
  }

  // MARK: - Frame loading

  func loadInitialFrame() {
    guard !screenshots.isEmpty, currentImage == nil else { return }
    loadFrame(at: index)
  }

  private func loadFrame(at target: Int) {
    requestID += 1
    let request = requestID
    isLoading = true

    Task { [weak self] in
      guard let self else { return }
      let image = await self.loader.image(at: target)
      // A newer seek superseded this one; its frame is the one that matters.
      guard request == self.requestID else { return }
      if let image { self.currentImage = image }
      self.isLoading = false
      // Prefetch forward and back: scrubbing reverses direction constantly.
      self.loader.prefetch(after: target, lookahead: 3)
      self.loader.prefetch(after: max(0, target - 4), lookahead: 3)
    }
  }
}
