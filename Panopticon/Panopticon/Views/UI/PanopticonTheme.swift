//
//  PanopticonTheme.swift
//  Panopticon
//
//  The single source of truth for Panopticon's visual language.
//
//  Ported from the reference design system, which is a light, dense,
//  cool-neutral UI: white surfaces on an off-white canvas, hairline borders
//  instead of heavy dividers, small type (11–13pt), 28pt controls, and
//  layered low-opacity shadows rather than big soft drops.
//
//  Token names mirror the reference CSS variables one-to-one so the two stay
//  legible against each other:
//
//      --canvas --surface --inset --hover      ->  Palette.canvas / surface / inset / hover
//      --line --line-strong                    ->  Palette.line / lineStrong
//      --ink --ink-2 --ink-3                   ->  Palette.ink / ink2 / ink3
//      --accent --accent-tint --accent-ink     ->  Palette.accent / accentTint / accentInk
//      --green --orange --orange-tint --red    ->  Palette.green / orange / orangeTint / red
//
//  Every shadow in the reference is built on rgba(16, 24, 40, …) — a cool
//  slate — so the whole neutral ramp is anchored to #101828 rather than the
//  warm browns this app used before.
//
//  Note: the reference only specifies a light palette, so that is what is
//  implemented here. The app currently pins itself to light mode. Adding dark
//  support should mean giving these tokens dynamic values, not sprinkling
//  colorScheme checks at call sites.
//

import SwiftUI

enum Theme {

  // MARK: - Palette

  enum Palette {
    /// Page background. Everything else sits on top of this.
    static let canvas = Color(hex: "F9FAFB")
    /// Raised surfaces: cards, popovers, default buttons.
    static let surface = Color(hex: "FFFFFF")
    /// Recessed areas: card footers, header bars, chips, badges.
    static let inset = Color(hex: "F4F5F7")
    /// Hover feedback on interactive rows and buttons.
    static let hover = Color(hex: "EFF1F4")
    /// Pressed / selected fill, one step past hover.
    static let active = Color(hex: "E7EAEF")

    /// Hairline borders and dividers.
    static let line = Color(hex: "EAECF0")
    /// Stronger line: unfilled meter segments, focus rings, emphasized rules.
    static let lineStrong = Color(hex: "D0D5DD")

    /// Primary text.
    static let ink = Color(hex: "101828")
    /// Secondary text: body copy, descriptions.
    static let ink2 = Color(hex: "475467")
    /// Muted text: metadata, counts, labels.
    static let ink3 = Color(hex: "98A2B3")

    /// Accent, used for primary actions and emphasis.
    static let accent = Color(hex: "2F6FEC")
    /// Accent background wash, e.g. inline code chips.
    static let accentTint = Color(hex: "EFF4FF")
    /// Accent-on-tint foreground, dark enough to read on `accentTint`.
    static let accentInk = Color(hex: "1849A9")

    static let green = Color(hex: "1F7A5F")
    static let greenTint = Color(hex: "BFF3DD")
    static let orange = Color(hex: "E56D24")
    static let orangeTint = Color(hex: "FFD6B8")
    static let red = Color(hex: "D92D20")
    static let redTint = Color(hex: "FEE4E2")

    /// Foreground for filled accent / ink buttons.
    static let onAccent = Color.white
    /// Foreground on an inverted (ink-filled) surface.
    static let onInk = canvas
  }

  // MARK: - Radii

  enum Radius {
    /// Cards, sheets, large containers.
    static let card: CGFloat = 12
    /// Buttons, inputs, list rows.
    static let control: CGFloat = 8
    /// Chips, inline code, small badges.
    static let chip: CGFloat = 6
    /// Tiny square glyph badges.
    static let glyph: CGFloat = 4
  }

  // MARK: - Metrics

  enum Metric {
    /// Standard control height (`h-7` in the reference).
    static let control: CGFloat = 28
    /// Chip / pill height (`h-6`).
    static let chip: CGFloat = 24
    /// Badge height (`h-5`).
    static let badge: CGFloat = 20

    static let cardPadding: CGFloat = 14
    static let cardPaddingCompact: CGFloat = 12
    /// Footers and header bars sit tighter than card bodies.
    static let barPaddingH: CGFloat = 12
    static let barPaddingV: CGFloat = 10

    static let gap: CGFloat = 8
    static let gapTight: CGFloat = 6
    static let hairline: CGFloat = 1
  }

  // MARK: - Typography
  //
  // The reference uses the platform UI sans, so this maps to the macOS system
  // face rather than a bundled webfont. Sizes are carried over verbatim
  // (13 / 12.5 / 12 / 11.5 / 11) and numerals are monospaced wherever the
  // reference sets `tabular-nums`.

  enum Font_ {
    /// Card and section titles. 13 semibold.
    static let title = Font.system(size: 13, weight: .semibold)
    /// Emphasized label. 12.5 medium.
    static let label = Font.system(size: 12.5, weight: .medium)
    /// Body copy. 13 regular, pairs with `ink2`.
    static let body = Font.system(size: 13, weight: .regular)
    /// Dense body / row text. 12.5 regular.
    static let bodyTight = Font.system(size: 12.5, weight: .regular)
    /// Metadata. 12 regular.
    static let caption = Font.system(size: 12, weight: .regular)
    /// Small metadata label. 11.5 medium.
    static let captionStrong = Font.system(size: 11.5, weight: .medium)
    /// Smallest label. 11 medium.
    static let micro = Font.system(size: 11, weight: .medium)
    /// Inline code chips. 12 monospaced.
    static let mono = Font.system(size: 12, design: .monospaced)

    /// Larger headings, used by onboarding rather than dense chrome.
    static func heading(_ size: CGFloat) -> Font {
      Font.system(size: size, weight: .semibold)
    }

    /// Numeric runs that should not jitter as values change.
    static func tabular(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> Font {
      Font.system(size: size, weight: weight).monospacedDigit()
    }
  }

  // MARK: - Motion
  //
  // Expressive-out easing: fast start, long settle. The two curves below are
  // the reference's `cubic-bezier(0.16, 1, 0.3, 1)` and
  // `cubic-bezier(0.23, 1, 0.32, 1)`.

  enum Motion {
    /// Color / opacity feedback. 100ms.
    static let feedback = Animation.easeOut(duration: 0.1)
    /// Button state changes. 150ms.
    static let control = Animation.easeOut(duration: 0.15)
    /// Content fades. 180ms.
    static let fade = Animation.easeOut(duration: 0.18)
    /// Drawer / disclosure. 300ms, expressive-out.
    static let drawer = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.3)
    /// Entrances. 400ms, expressive-out.
    static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.4)

    /// Pressed-state scale on controls (`active:scale-[0.96]`).
    static let pressedScale: CGFloat = 0.96
  }

  // MARK: - Elevation
  //
  // Shadows are layered: a hairline ring for definition plus a short drop for
  // lift. Anchored on #101828 at low opacity, matching the reference.

  enum Shadow {
    struct Layer {
      let color: Color
      let radius: CGFloat
      let y: CGFloat
    }

    private static func slate(_ opacity: Double) -> Color {
      Color(hex: "101828").opacity(opacity)
    }

    /// Ring only — for flush elements that need an edge, not lift.
    static let hairline: [Layer] = [
      Layer(color: slate(0.06), radius: 0, y: 0)
    ]

    /// Default buttons and chips.
    static let button: [Layer] = [
      Layer(color: slate(0.08), radius: 0.5, y: 0),
      Layer(color: slate(0.06), radius: 1, y: 1),
    ]

    /// Cards.
    static let card: [Layer] = [
      Layer(color: slate(0.06), radius: 0.5, y: 0),
      Layer(color: slate(0.08), radius: 3, y: 1),
      Layer(color: slate(0.05), radius: 12, y: 4),
    ]

    /// Modals and popovers.
    static let overlay: [Layer] = [
      Layer(color: slate(0.08), radius: 0.5, y: 0),
      Layer(color: slate(0.12), radius: 24, y: 8),
    ]
  }
}

// MARK: - View helpers

extension View {
  /// Applies a layered elevation from `Theme.Shadow`.
  func elevation(_ layers: [Theme.Shadow.Layer]) -> some View {
    layers.reduce(AnyView(self)) { view, layer in
      AnyView(view.shadow(color: layer.color, radius: layer.radius, x: 0, y: layer.y))
    }
  }

  /// A raised surface: fill, hairline border, radius, elevation.
  func cardSurface(
    radius: CGFloat = Theme.Radius.card,
    fill: Color = Theme.Palette.surface,
    elevation layers: [Theme.Shadow.Layer] = Theme.Shadow.card
  ) -> some View {
    self
      .background(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(fill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metric.hairline)
      )
      .elevation(layers)
  }

  /// A hairline rule, used instead of a heavy divider.
  func hairlineBorder(_ radius: CGFloat = Theme.Radius.control) -> some View {
    overlay(
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metric.hairline)
    )
  }
}
