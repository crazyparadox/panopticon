import XCTest

@testable import Panopticon

/// The scrubber maps a position on the track to the nearest capture via binary
/// search. Off-by-one there means the frame on screen disagrees with the time
/// chip, so the search and the fraction math are pinned down here.
@MainActor
final class DayScrubberModelTests: XCTestCase {
  private let dayStart = Date(timeIntervalSince1970: 1_000_000)
  private var dayEnd: Date { dayStart.addingTimeInterval(86400) }

  /// Captures at fixed hour offsets, with a deliberate gap between hour 4 and
  /// hour 12 to stand in for an idle stretch.
  private func makeModel(hourOffsets: [Double]) -> DayScrubberModel {
    let shots = hourOffsets.enumerated().map { index, hours in
      Screenshot(
        id: Int64(index),
        capturedAt: Int(dayStart.timeIntervalSince1970 + hours * 3600),
        filePath: "/tmp/frame-\(index).jpg",
        fileSize: nil,
        idleSecondsAtCapture: nil,
        isDeleted: false
      )
    }
    return DayScrubberModel(screenshots: shots, dayStart: dayStart, dayEnd: dayEnd)
  }

  func testSeekLandsOnNearestCaptureAcrossAGap() {
    let model = makeModel(hourOffsets: [1, 2, 3, 4, 12, 13])

    // Just after hour 4 is still closest to the hour-4 capture, not the one at
    // hour 12 on the far side of the gap.
    model.seek(to: dayStart.addingTimeInterval(5 * 3600))
    XCTAssertEqual(model.index, 3)

    // Past the midpoint of the gap it should snap forward instead.
    model.seek(to: dayStart.addingTimeInterval(9 * 3600))
    XCTAssertEqual(model.index, 4)
  }

  func testSeekClampsOutsideTheCapturedRange() {
    let model = makeModel(hourOffsets: [6, 7, 8])

    model.seek(to: dayStart)
    XCTAssertEqual(model.index, 0, "before the first capture should clamp to it")

    model.seek(to: dayEnd)
    XCTAssertEqual(model.index, 2, "after the last capture should clamp to it")
  }

  func testSeekPicksTheExactCaptureWhenTimesMatch() {
    let model = makeModel(hourOffsets: [1, 5, 9, 13, 17])
    for (expected, hour) in [1, 5, 9, 13, 17].enumerated() {
      model.seek(to: dayStart.addingTimeInterval(Double(hour) * 3600))
      XCTAssertEqual(model.index, expected, "hour \(hour) should select capture \(expected)")
    }
  }

  func testFittingTheDayMakesFractionSpanTheWholeLogicalDay() {
    // Captures cover only hours 6-12, but a fitted track represents the whole
    // day, so a 6am capture sits a quarter of the way along, not at zero.
    let model = makeModel(hourOffsets: [6, 12])
    model.zoomToFit()
    XCTAssertEqual(model.fraction(of: model.screenshots[0]), 0.25, accuracy: 0.0001)
    XCTAssertEqual(model.fraction(of: model.screenshots[1]), 0.5, accuracy: 0.0001)
  }

  func testSeekToFractionIsInverseOfFractionWhenTheDayIsFitted() {
    let model = makeModel(hourOffsets: [2, 8, 14, 20])
    model.zoomToFit()
    for expected in model.screenshots.indices {
      model.seek(toFraction: model.fraction(of: model.screenshots[expected]))
      XCTAssertEqual(model.index, expected)
    }
  }

  func testSeekToFractionClampsOutOfRangeInput() {
    let model = makeModel(hourOffsets: [3, 9, 15])
    model.zoomToFit()
    model.seek(toFraction: -4)
    XCTAssertEqual(model.index, 0)
    model.seek(toFraction: 12)
    XCTAssertEqual(model.index, 2)
  }

  // MARK: - Window

  func testOpensZoomedInOnTheMostRecentCaptures() {
    let model = makeModel(hourOffsets: [1, 5, 9, 13, 17])
    XCTAssertLessThan(
      model.visibleSpan, model.daySpan, "the track should not open showing the whole day")
    model.jumpToEnd()
    let f = model.fraction(of: model.screenshots[model.screenshots.count - 1])
    XCTAssertTrue((0...1).contains(f), "the newest capture should be on the visible track, got \(f)")
  }

  /// The window must hold still while the playhead moves inside it, otherwise a
  /// drag would slide the playhead back under the cursor and fight the user.
  func testWindowHoldsStillWhileThePlayheadMovesWithinIt() {
    // Captures a minute apart sit well inside the default one-hour window.
    let model = makeModel(hourOffsets: (0..<20).map { 6 + Double($0) / 60.0 })
    model.seek(to: model.screenshots[9].capturedDate)
    let before = model.windowStart
    model.step(by: 1)
    model.step(by: 1)
    XCTAssertEqual(before, model.windowStart)
  }

  func testWindowFollowsThePlayheadOffTheEdge() {
    let model = makeModel(hourOffsets: [1, 5, 9, 13, 17, 21])
    model.seek(to: model.screenshots[0].capturedDate)
    let atStart = model.windowStart
    // Four hours away is far outside a one-hour window.
    model.step(by: 1)
    XCTAssertNotEqual(atStart, model.windowStart, "window should scroll to follow the playhead")
    let f = model.fraction(of: model.screenshots[1])
    XCTAssertTrue((0...1).contains(f), "playhead should be back on the track, got \(f)")
  }

  func testWindowNeverScrollsPastEitherEndOfTheDay() {
    let model = makeModel(hourOffsets: [0, 6, 12, 18, 23.9])
    model.jumpToStart()
    XCTAssertGreaterThanOrEqual(model.windowStart, dayStart)
    model.jumpToEnd()
    XCTAssertLessThanOrEqual(model.windowEnd.timeIntervalSince1970, dayEnd.timeIntervalSince1970 + 1)
  }

  func testZoomStepsStayWithinTheDayAndReanchor() {
    let model = makeModel(hourOffsets: [8, 9, 10])
    model.seek(to: model.screenshots[1].capturedDate)
    while model.canZoomOut { model.zoomOut() }
    XCTAssertLessThanOrEqual(model.visibleSpan, model.daySpan)
    while model.canZoomIn { model.zoomIn() }
    // Whatever the zoom, the playhead must remain reachable on the track.
    let f = model.fraction(of: model.screenshots[1])
    XCTAssertTrue((0...1).contains(f), "playhead fell off the track at max zoom, got \(f)")
  }

  // MARK: - Sessions

  func testSessionsSplitOnLongGapsOnly() {
    // Two runs a minute apart internally, separated by four hours of nothing.
    let morning = (0..<5).map { 9 + Double($0) / 60.0 }
    let afternoon = (0..<4).map { 14 + Double($0) / 60.0 }
    let model = makeModel(hourOffsets: morning + afternoon)
    XCTAssertEqual(model.sessions.count, 2)
    XCTAssertEqual(model.sessions[0].frameCount, 5)
    XCTAssertEqual(model.sessions[1].frameCount, 4)
  }

  func testSessionsCoverEveryCaptureExactlyOnce() {
    let model = makeModel(hourOffsets: [1, 2, 3, 12, 13, 20])
    let covered = model.sessions.flatMap { Array($0.startIndex...$0.endIndex) }
    XCTAssertEqual(covered.sorted(), Array(model.screenshots.indices))
  }

  func testAdjacentSessionNavigationSkipsIdleTime() {
    let model = makeModel(hourOffsets: [1, 2, 3, 12, 13, 20])
    model.jumpToStart()
    XCTAssertEqual(model.currentSession?.id, 0)
    model.goToAdjacentSession(forward: true)
    XCTAssertEqual(model.currentSession?.id, 1)
    model.goToAdjacentSession(forward: false)
    XCTAssertEqual(model.currentSession?.id, 0)
  }

  func testAdjacentSessionNavigationClampsAtTheEnds() {
    let model = makeModel(hourOffsets: [1, 12, 20])
    model.jumpToStart()
    model.goToAdjacentSession(forward: false)
    XCTAssertEqual(model.index, 0)
    model.jumpToEnd()
    model.goToAdjacentSession(forward: true)
    XCTAssertEqual(model.index, model.screenshots.count - 1)
  }

  func testStepClampsAtBothEnds() {
    let model = makeModel(hourOffsets: [1, 2, 3])
    model.jumpToStart()
    model.step(by: -5)
    XCTAssertEqual(model.index, 0)
    model.step(by: 99)
    XCTAssertEqual(model.index, 2)
  }

  func testEmptyDayIsInertRatherThanCrashing() {
    let model = makeModel(hourOffsets: [])
    XCTAssertTrue(model.isEmpty)
    XCTAssertNil(model.currentScreenshot)
    // None of these have a valid index to move to; they must not trap.
    model.seek(toFraction: 0.5)
    model.step(by: 3)
    model.jumpToEnd()
    XCTAssertEqual(model.index, 0)
    XCTAssertNil(model.currentDate)
  }
}
