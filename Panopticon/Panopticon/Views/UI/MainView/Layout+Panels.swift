//
//  Layout+Panels.swift
//  Panopticon
//

import SwiftUI

struct TimelineCalendarButtonFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect = .zero

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

enum TimelineAlignment {
  static let topInset: CGFloat = 24
  static let pickerRowOffset: CGFloat = -10
  static let categoryRowInset: CGFloat = 55
  static let headerContentGap: CGFloat = 18
}

enum TimelineNavigationLayout {
  static let arrowSize: CGFloat = 24
  static let hoverCircleSize: CGFloat = 30
  static let calendarGap: CGFloat = 4
}

enum LogoPosition {
  static let logoSize: CGFloat = 48
  static let logoVerticalOffset: CGFloat = 8
}

extension MainView {
  var contentStack: some View {
    // Single panel filling the window. The scrubber supplies its own search
    // and settings controls, so there is no outer shell chrome.
    rightPanel
      .padding(0)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }


  @ViewBuilder
  private var rightPanel: some View {
    // Right column: Main white panel including header + content
    ZStack {
      switch selectedIcon {
      case .settings:
        SettingsView()
          .padding(15)
      case .timeline:
        GeometryReader { geo in
          timelinePanel(geo: geo)
        }
      }
    }
    .padding(0)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // A single rounded clip matching the window. Anything nested inside this
    // with its own radius reads as a second border.
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func timelinePanel(geo: GeometryProxy) -> some View {
    ZStack(alignment: .topLeading) {
      HStack(alignment: .top, spacing: 0) {
        timelineLeftColumn
          .zIndex(1)
        Rectangle()
          .fill(Theme.Palette.line)
          .frame(width: timelineInspectorDividerWidth)
          .opacity(timelineInspectorDividerWidth == 0 ? 0 : 1)
          .frame(maxHeight: .infinity)
        timelineRightColumn(geo: geo)
      }
    }
    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
    .coordinateSpace(name: "TimelinePanel")
    .overlay(alignment: .topLeading) {
      timelineCalendarPopoverOverlay(panelWidth: geo.size.width)
    }
    .onPreferenceChange(TimelineCalendarButtonFramePreferenceKey.self) { frame in
      timelineCalendarButtonFrame = frame
    }
  }

  private var timelineLeftColumn: some View {
    // The scrubber owns the full surface and supplies its own chrome: search
    // and settings top-left, the date pill bottom-left. No outer header, no
    // weekly-hours footer, no padding to inset it.
    timelineContent
      .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .coordinateSpace(name: "TimelinePane")
  }

  private var timelineContent: some View {
    DayScrubberFrames(
      selectedDate: $selectedDate,
      onOpenSettings: { selectedIcon = .settings },
      onOpenDatePicker: { showDatePicker = true }
    )
    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .environmentObject(categoryStore)
    .opacity(contentOpacity)
  }


  private func timelineRightColumn(geo: GeometryProxy) -> some View {
    ZStack(alignment: .topLeading) {
      if timelineInspectorWidth > 0 {
        Color.white.opacity(0.7)
      }

      switch timelineMode {
      case .day:
        dayTimelineInspectorContent(geo: geo)
      case .week:
        weekTimelineInspectorContent(geo: geo)
      case .frames:
        // Zero-width column in this mode; nothing to render.
        EmptyView()
      }
    }
    .frame(width: timelineInspectorWidth)
    .frame(maxHeight: .infinity)
    .opacity(contentOpacity)
    .clipped()
    .clipShape(
      UnevenRoundedRectangle(
        cornerRadii: .init(
          topLeading: 0,
          bottomLeading: 0, bottomTrailing: 8, topTrailing: 8
        )
      )
    )
    .contentShape(
      UnevenRoundedRectangle(
        cornerRadii: .init(
          topLeading: 0,
          bottomLeading: 0, bottomTrailing: 8, topTrailing: 8
        )
      )
    )
  }

  @ViewBuilder
  private func dayTimelineInspectorContent(geo: GeometryProxy) -> some View {
    if let activity = selectedActivity {
      timelineActivityInspector(activity: activity, geo: geo)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    } else {
      VStack(spacing: 8) {
        Spacer()
        Image(systemName: "cursorarrow.click.2")
          .font(.system(size: 22))
          .foregroundColor(Color.black.opacity(0.25))
        Text("Select a card to see details")
          .font(.system(size: 12.5))
          .foregroundColor(Color.black.opacity(0.4))
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
  }

  @ViewBuilder
  private func weekTimelineInspectorContent(geo: GeometryProxy) -> some View {
    if let activity = selectedActivity, isWeekTimelineInspectorVisible {
      timelineActivityInspector(activity: activity, geo: geo)
        .id(activity.id)
        .opacity(weekInspectorContentVisible ? 1 : 0)
        .offset(x: weekInspectorContentVisible ? 0 : 10)
        .animation(inspectorContentAnimation, value: weekInspectorContentVisible)
        .transition(.opacity.combined(with: .offset(x: 10)))
    }
  }

  private func timelineActivityInspector(activity: TimelineActivity, geo: GeometryProxy)
    -> some View
  {
    ZStack(alignment: .bottom) {
      ActivityCard(
        activity: activity,
        maxHeight: geo.size.height,
        scrollSummary: true,
        hasAnyActivities: hasAnyActivities,
        onCategoryChange: { category, activity in
          handleCategoryChange(to: category, for: activity)
        },
        onNavigateToCategoryEditor: {
          showCategoryEditor = true
        },
        onRetryBatchCompleted: { batchId in
          refreshActivitiesTrigger &+= 1
          if selectedActivity?.batchId == batchId {
            clearTimelineSelection()
          }
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }



  private var copyTimelineButton: some View {
    let background = Theme.Palette.inset
    let stroke = Theme.Palette.inset
    let textColor = Theme.Palette.accent

    // Slide up + fade: no text scaling (scaling distorts letterforms)
    let enterTransition = AnyTransition.opacity
      .combined(with: .move(edge: .bottom))
    let exitTransition = AnyTransition.opacity
      .combined(with: .move(edge: .top))

    return Button(action: copyTimelineToClipboard) {
      ZStack {
        if copyTimelineState == .copying {
          ProgressView()
            .scaleEffect(0.6)
            .progressViewStyle(CircularProgressViewStyle(tint: textColor))
            .transition(.asymmetric(insertion: enterTransition, removal: exitTransition))
        } else if copyTimelineState == .copied {
          HStack(spacing: 4) {
            Image(systemName: "checkmark")
              .font(.system(size: 11.5, weight: .medium))
            Text("Copied")
              .font(Font.system(size: 11.5).weight(.medium))
          }
          .transition(.asymmetric(insertion: enterTransition, removal: exitTransition))
        } else {
          HStack(spacing: 4) {
            Image("Copy")
              .resizable()
              .interpolation(.high)
              .renderingMode(.template)
              .scaledToFit()
              .frame(width: 11.5, height: 11.5)
            Text("Copy timeline")
              .font(Font.system(size: 11.5).weight(.medium))
          }
          .transition(.asymmetric(insertion: enterTransition, removal: exitTransition))
        }
      }
      .animation(.spring(response: 0.3, dampingFraction: 0.85), value: copyTimelineState)
      .frame(width: 104, height: 23)
      .foregroundColor(textColor)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .overlay(
        RoundedRectangle(cornerRadius: 7)
          .inset(by: 0.5)
          .stroke(stroke, lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(ShrinkButtonStyle())
    .disabled(copyTimelineState == .copying)
    .hoverScaleEffect(
      enabled: copyTimelineState != .copying,
      scale: 1.02
    )
    .pointingHandCursorOnHover(
      enabled: copyTimelineState != .copying,
      reassertOnPressEnd: true
    )
    .accessibilityLabel(Text("Copy timeline to clipboard"))
  }
}

private struct ShrinkButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .panopticonPressScale(
        configuration.isPressed,
        pressedScale: 0.97,
        animation: .spring(response: 0.25, dampingFraction: 0.7)
      )
  }
}
