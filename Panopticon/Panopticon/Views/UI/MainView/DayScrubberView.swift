//
//  DayScrubberView.swift
//  Panopticon
//
//  Browsing a day's captures. Layout follows the reference: a search field and
//  gear at the top left with the moment's title centred, the frame on its own in
//  the middle, a date pill at the bottom left, and a segmented session track
//  across the bottom with zoom controls at the bottom right. The track shows a
//  window onto the day rather than all of it at once.
//

import AppKit
import SwiftUI

struct DayScrubberView: View {
  @StateObject private var model: DayScrubberModel
  private let initialDate: Date?
  /// Cards for the day, used for the title above the frame and for search.
  private let cards: [TimelineCard]
  private let onOpenSettings: () -> Void
  private let onOpenDatePicker: () -> Void

  @State private var isDragging = false
  @State private var scrollResidue: CGFloat = 0
  @State private var keyMonitor: Any?
  @State private var query = ""
  @FocusState private var searchFocused: Bool

  init(
    screenshots: [Screenshot],
    dayStart: Date,
    dayEnd: Date,
    cards: [TimelineCard] = [],
    initialDate: Date? = nil,
    onOpenSettings: @escaping () -> Void = {},
    onOpenDatePicker: @escaping () -> Void = {}
  ) {
    _model = StateObject(
      wrappedValue: DayScrubberModel(
        screenshots: screenshots, dayStart: dayStart, dayEnd: dayEnd))
    self.initialDate = initialDate
    self.cards = cards
    self.onOpenSettings = onOpenSettings
    self.onOpenDatePicker = onOpenDatePicker
  }

  private static let chipFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
    return formatter
  }()

  var body: some View {
    ZStack {
      backdrop

      VStack(spacing: 0) {
        topBar
        carousel
        trackArea
      }
    }
    .overlay(alignment: .bottomLeading) { datePill }
    .overlay(alignment: .bottomTrailing) { zoomControls }
    .onAppear(perform: handleAppear)
    .onDisappear(perform: handleDisappear)
  }

  // MARK: - Backdrop

  /// The surface is the desktop showing through the window, not a painted
  /// colour. The earlier gradient only imitated the lavender of one particular
  /// wallpaper; this tracks whatever is actually behind the window. A thin white
  /// scrim goes over it so the chrome stays legible on a dark or busy desktop.
  private var backdrop: some View {
    ZStack {
      VisualEffectBackground(material: .hudWindow)
      Color.white.opacity(0.10)
    }
    .ignoresSafeArea()
  }

  // MARK: - Top bar

  private var topBar: some View {
    ZStack {
      // The backdrop is now whatever the user's desktop happens to be, so bare
      // ink text had no dependable contrast. Sitting it on the same surface pill
      // as the other controls makes it legible over any wallpaper.
      Text(currentTitle)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundColor(Theme.Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Theme.Palette.surface)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(Theme.Palette.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, 250)

      HStack(spacing: 9) {
        searchField
        gearButton
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 6)
    .zIndex(20)
  }

  private var searchField: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(Theme.Palette.ink2)
      TextField("Search All", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(Theme.Palette.ink)
        .frame(width: 128)
        .focused($searchFocused)
      // Mirrors the reference's key hint; the key monitor honours it.
      Text("/")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(Theme.Palette.ink3)
        .frame(width: 16, height: 16)
        .background(
          RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
            .fill(Theme.Palette.inset)
        )
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(Theme.Palette.surface)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .stroke(Theme.Palette.line, lineWidth: 1)
    )
    .overlay(alignment: .topLeading) { searchResults }
  }

  @ViewBuilder
  private var searchResults: some View {
    if !query.isEmpty {
      let matches = searchMatches
      VStack(alignment: .leading, spacing: 0) {
        if matches.isEmpty {
          Text("Nothing matched")
            .font(.system(size: 12))
            .foregroundColor(Theme.Palette.ink3)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
        } else {
          ForEach(matches, id: \.id) { card in
            Button {
              if let start = cardStart(card) {
                model.seek(to: start)
                query = ""
                searchFocused = false
              }
            } label: {
              VStack(alignment: .leading, spacing: 1) {
                Text(card.title)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundColor(Theme.Palette.ink)
                  .lineLimit(1)
                Text("\(card.startTimestamp) · \(card.category)")
                  .font(.system(size: 10.5))
                  .foregroundColor(Theme.Palette.ink3)
                  .lineLimit(1)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 11)
              .padding(.vertical, 7)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
          }
        }
      }
      .frame(width: 264, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(Theme.Palette.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(Theme.Palette.line, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
      .offset(y: 44)
    }
  }

  private var gearButton: some View {
    Button(action: onOpenSettings) {
      Image(systemName: "gearshape.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(Theme.Palette.ink2)
        .frame(width: 34, height: 34)
        .background(
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Theme.Palette.surface)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(Theme.Palette.line, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help("Settings")
  }

  // MARK: - Carousel

  /// The frame on its own. Consecutive captures are seconds apart, so showing
  /// the neighbours behind it just looked like a duplicate of the same shot.
  private var carousel: some View {
    GeometryReader { geo in
      ZStack {
        // Fills rather than fits. Fitting kept the card height-limited on a
        // wide window, which is exactly what left bars down both sides; filling
        // takes the full width and crops a little off the top and bottom.
        frameCard
          .aspectRatio(frameAspect, contentMode: .fill)
          .frame(width: geo.size.width, height: geo.size.height)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: .black.opacity(0.22), radius: 26, y: 8)
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .contentShape(Rectangle())
      .onScrollWheel { handleScroll($0) }
      .overlay(alignment: .leading) { chevron(forward: false).padding(.leading, 4) }
      .overlay(alignment: .trailing) { chevron(forward: true).padding(.trailing, 4) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Aspect of the capture on screen, falling back to 16:10 (the common Mac
  /// display shape) until the first frame decodes.
  private var frameAspect: CGFloat {
    guard let image = model.currentImage, image.height > 0 else { return 1.6 }
    return CGFloat(image.width) / CGFloat(image.height)
  }

  private var frameCard: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Theme.Palette.ink)
      if let image = model.currentImage {
        ScreenshotSlideshowLayerBackedImageView(image: image)
      } else {
        ProgressView().controlSize(.small)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func chevron(forward: Bool) -> some View {
    Button {
      model.goToAdjacentSession(forward: forward)
    } label: {
      Image(systemName: forward ? "chevron.right" : "chevron.left")
        .font(.system(size: 19, weight: .medium))
        .foregroundColor(Theme.Palette.ink2.opacity(0.75))
        .frame(width: 30, height: 60)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help(forward ? "Next session" : "Previous session")
  }

  // MARK: - Date pill

  private var datePill: some View {
    Button(action: onOpenDatePicker) {
      HStack(spacing: 7) {
        Image(systemName: "calendar")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(Theme.Palette.ink2)
        Text(model.currentDate.map(Self.chipFormatter.string(from:)) ?? "No capture")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(Theme.Palette.ink)
          .monospacedDigit()
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundColor(Theme.Palette.ink3)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(Theme.Palette.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(Theme.Palette.line, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .padding(.leading, 16)
    .padding(.bottom, 146)
  }

  // MARK: - Zoom controls

  private var zoomControls: some View {
    HStack(spacing: 9) {
      Button { model.zoomToFit() } label: {
        Image(systemName: "arrow.left.and.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(Theme.Palette.ink2)
          .frame(width: 34, height: 34)
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .background(pillBackground)
      .help("Fit the whole day")

      HStack(spacing: 0) {
        zoomButton(systemName: "minus.magnifyingglass", enabled: model.canZoomOut) {
          model.zoomOut()
        }
        zoomButton(systemName: "plus.magnifyingglass", enabled: model.canZoomIn) {
          model.zoomIn()
        }
      }
      .background(pillBackground)
    }
    .padding(.trailing, 16)
    .padding(.bottom, 146)
  }

  private func zoomButton(systemName: String, enabled: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(enabled ? Theme.Palette.ink2 : Theme.Palette.ink3.opacity(0.5))
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .disabled(!enabled)
  }

  private var pillBackground: some View {
    RoundedRectangle(cornerRadius: 11, style: .continuous)
      .fill(Theme.Palette.surface)
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(Theme.Palette.line, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
  }

  // MARK: - Track

  private var trackArea: some View {
    GeometryReader { geo in
      let inset: CGFloat = 34
      let usable = max(1, geo.size.width - inset * 2)

      ZStack(alignment: .leading) {
        // Baseline spans the visible window, including time never recorded.
        Capsule()
          .fill(Color.white.opacity(0.78))
          .frame(width: usable, height: 14)
          .offset(x: inset)

        ForEach(visibleSessions, id: \.id) { session in
          sessionBar(session, usable: usable, inset: inset)
        }
        ForEach(visibleSessions, id: \.id) { session in
          sessionMarker(session, usable: usable, inset: inset)
        }
        playhead(usable: usable, inset: inset)
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
      .contentShape(Rectangle())
      .gesture(dragGesture(usable: usable, inset: inset))
    }
    .frame(height: 132)
  }

  /// Sessions intersecting the visible window; the rest are scrolled off.
  private var visibleSessions: [CaptureSession] {
    model.sessions.filter {
      model.fraction(of: $0.end) >= -0.02 && model.fraction(of: $0.start) <= 1.02
    }
  }

  private func sessionBar(_ session: CaptureSession, usable: CGFloat, inset: CGFloat) -> some View {
    let startF = min(1, max(0, model.fraction(of: session.start)))
    let endF = min(1, max(0, model.fraction(of: session.end)))
    let x = inset + usable * CGFloat(startF)
    // Floor the width so a very short session is still a visible tick.
    let width = max(8, usable * CGFloat(endF - startF))
    let isCurrent = model.currentSession?.id == session.id

    return Capsule()
      .fill(isCurrent ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.5))
      .frame(width: width, height: 18)
      .offset(x: x)
      .onTapGesture { model.jump(to: session) }
  }

  /// Every session keeps its app icon, including the one being played. The
  /// active one is marked by its ring, not by replacing the icon.
  private func sessionMarker(_ session: CaptureSession, usable: CGFloat, inset: CGFloat)
    -> some View
  {
    let startF = min(1, max(0, model.fraction(of: session.start)))
    let x = inset + usable * CGFloat(startF)

    return Button { model.jump(to: session) } label: {
      sessionIcon(for: session)
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help(sessionTooltip(for: session))
    .offset(x: x - 19)
  }

  /// The app or site that dominated the session, drawn from the same favicon
  /// pipeline the activity cards use. Falls back to a neutral marker when the
  /// day has not been analysed yet and there is no card to read an app from.
  @ViewBuilder
  private func sessionIcon(for session: CaptureSession) -> some View {
    let card = card(at: session.start)
    let primaryRaw = card?.appSites?.primary
    let secondaryRaw = card?.appSites?.secondary
    let isCurrent = model.currentSession?.id == session.id

    ZStack {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(Theme.Palette.surface)
        .frame(width: 38, height: 38)
        .overlay(
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(
              isCurrent ? Theme.Palette.accent : Theme.Palette.lineStrong,
              lineWidth: isCurrent ? 2 : 1))

      if primaryRaw != nil || secondaryRaw != nil {
        FaviconImageView(
          primaryRaw: primaryRaw,
          secondaryRaw: secondaryRaw,
          primaryHost: FaviconService.normalizedHost(from: primaryRaw),
          secondaryHost: FaviconService.normalizedHost(from: secondaryRaw),
          size: 22,
          cornerRadius: 5
        )
      } else {
        Circle().stroke(Theme.Palette.ink3, lineWidth: 2).frame(width: 16, height: 16)
      }
    }
    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
  }

  private func sessionTooltip(for session: CaptureSession) -> String {
    guard let card = card(at: session.start) else { return "Jump to this session" }
    return card.appSites?.primary ?? card.title
  }

  private func playhead(usable: CGFloat, inset: CGFloat) -> some View {
    let f = min(1, max(0, model.currentFraction))
    let x = inset + usable * CGFloat(f)
    return RoundedRectangle(cornerRadius: 3, style: .continuous)
      .fill(Color.white)
      .frame(width: 8, height: 74)
      .overlay(
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .stroke(Theme.Palette.ink.opacity(0.14), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
      .offset(x: x - 4)
      .animation(isDragging ? nil : .interactiveSpring(response: 0.2), value: model.index)
  }

  private func dragGesture(usable: CGFloat, inset: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        isDragging = true
        model.stopPlayback()
        model.seek(toFraction: Double((value.location.x - inset) / usable))
      }
      .onEnded { _ in isDragging = false }
  }

  // MARK: - Title and search

  /// Card whose span contains an instant, if the day has been analysed.
  private func card(at moment: Date) -> TimelineCard? {
    cards.first { card in
      guard let start = cardStart(card), let end = cardEnd(card) else { return false }
      return moment >= start && moment <= end
    }
  }

  private var currentTitle: String {
    guard let now = model.currentDate else { return "No captures" }
    if let card = card(at: now) { return card.title }
    return model.currentSession == nil ? "Idle" : "Recording"
  }

  private var searchMatches: [TimelineCard] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return [] }
    return cards.filter {
      $0.title.lowercased().contains(needle) || $0.summary.lowercased().contains(needle)
        || $0.category.lowercased().contains(needle)
    }
    .prefix(6)
    .map { $0 }
  }

  /// Card timestamps are wall-clock strings for the logical day, so they are
  /// resolved against that day rather than parsed as absolute dates.
  private func cardStart(_ card: TimelineCard) -> Date? { resolve(card.startTimestamp) }

  private func cardEnd(_ card: TimelineCard) -> Date? {
    guard let start = cardStart(card), let end = resolve(card.endTimestamp) else { return nil }
    // A card ending after midnight wraps into the next calendar day.
    return end < start ? end.addingTimeInterval(86400) : end
  }

  private func resolve(_ timestamp: String) -> Date? {
    guard let minutes = parseTimeHMMA(timeString: timestamp) else { return nil }
    let base = Calendar.current.startOfDay(for: model.dayStart)
    let candidate = base.addingTimeInterval(TimeInterval(minutes) * 60)
    // The logical day runs 4am to 4am, so an early-morning time belongs to the
    // tail of the window rather than before its start.
    return candidate < model.dayStart ? candidate.addingTimeInterval(86400) : candidate
  }

  // MARK: - Input

  private func handleScroll(_ delta: CGFloat) {
    // Accumulate sub-frame deltas so a slow trackpad drag still advances exactly
    // one capture at a time instead of stalling or skipping.
    model.stopPlayback()
    scrollResidue += delta
    let steps = Int(scrollResidue / 6)
    guard steps != 0 else { return }
    scrollResidue -= CGFloat(steps) * 6
    model.step(by: steps)
  }

  private func handleAppear() {
    if let initialDate {
      model.seek(to: initialDate)
    } else {
      model.jumpToEnd()
    }
    model.loadInitialFrame()
    installKeyMonitor()
  }

  private func handleDisappear() {
    model.stopPlayback()
    removeKeyMonitor()
  }

  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Never swallow keys while the user is typing in the search field.
      if searchFocused { return event }
      switch event.keyCode {
      case 123:
        model.stopPlayback()
        model.step(by: event.modifierFlags.contains(.shift) ? -10 : -1)
        return nil
      case 124:
        model.stopPlayback()
        model.step(by: event.modifierFlags.contains(.shift) ? 10 : 1)
        return nil
      case 115: model.jumpToStart(); return nil  // home
      case 119: model.jumpToEnd(); return nil  // end
      case 49: model.togglePlayback(); return nil  // space
      case 24: model.zoomIn(); return nil  // =
      case 27: model.zoomOut(); return nil  // -
      default:
        // "/" focuses search, matching the hint in the field.
        if event.charactersIgnoringModifiers == "/" {
          searchFocused = true
          return nil
        }
        return event
      }
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }
}

// MARK: - Scroll wheel plumbing

extension View {
  /// SwiftUI has no scroll-wheel hook on macOS, so bridge one in. This has to be
  /// an overlay, not a background: scroll events travel up the responder chain
  /// from the view under the pointer, never sideways to a sibling behind it, so
  /// a catcher placed underneath the frame would never fire.
  func onScrollWheel(_ handler: @escaping (CGFloat) -> Void) -> some View {
    overlay(ScrollWheelCatcher(handler: handler))
  }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
  let handler: (CGFloat) -> Void

  func makeNSView(context: Context) -> CatcherView {
    let view = CatcherView()
    view.handler = handler
    return view
  }

  func updateNSView(_ nsView: CatcherView, context: Context) {
    nsView.handler = handler
  }

  final class CatcherView: NSView {
    var handler: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
      // Horizontal intent wins when present; otherwise vertical scrolling maps
      // onto the timeline so a plain mouse wheel still works.
      let horizontal = event.scrollingDeltaX
      let delta =
        abs(horizontal) > abs(event.scrollingDeltaY) ? -horizontal : -event.scrollingDeltaY
      handler?(delta)
    }
  }
}
