//
//  CategoryPickerView.swift
//  Panopticon
//

import SwiftUI

struct CategoryPickerView: View {
  let currentCategory: String
  let categories: [TimelineCategory]
  var onCategorySelected: (TimelineCategory) -> Void
  var onNavigateToEditor: () -> Void

  var body: some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: 0) {
        // Category pills section - wrap to as many rows as needed
        WrappingHStack(categories, spacing: 4, width: geometry.size.width - 16) { category in
          CategoryPill(
            category: category,
            isSelected: isCategorySelected(category),
            onTap: { onCategorySelected(category) }
          )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)

        // Divider - using a custom line with specific styling
        Rectangle()
          .fill(Color.clear)
          .frame(height: 0)
          .overlay(
            Rectangle()
              .fill(Theme.Palette.line)
              .frame(height: 1)
          )
          .padding(.horizontal, 0)

        // Helper text section
        VStack(alignment: .leading, spacing: 10) {
          ZStack(alignment: .topLeading) {
            // Main text
            HStack(alignment: .top, spacing: 0) {
              Text(
                "To help Panopticon organize your activities more accurately, try adding more details to the descriptions in your categories "
              )
              .font(Font.system(size: 10).weight(.medium))
              .foregroundColor(Theme.Palette.ink2)  // #635953

              Button(action: onNavigateToEditor) {
                Text("here")
                  .font(Font.system(size: 10).weight(.medium))
                  .foregroundColor(Theme.Palette.accent)  // #ff6600
                  .underline()
              }
              .buttonStyle(.plain)
              .pointingHandCursor()

              Text(".")
                .font(Font.system(size: 10).weight(.medium))
                .foregroundColor(Theme.Palette.ink2)
            }
            .padding(.leading, 2.188)

            // Lightbulb icon overlaid
            Image(systemName: "lightbulb.fill")
              .font(.system(size: 7))
              .foregroundColor(Theme.Palette.ink2)  // #7c7875
              .offset(x: 0, y: 2)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      ZStack {
        // Backdrop blur effect - rgba(250,244,241,0.86) with blur
        Theme.Palette.inset.opacity(0.86)
          .background(.ultraThinMaterial)
      }
      .overlay(
        // Border - #e9e1de
        UnevenRoundedRectangle(
          cornerRadii: .init(
            topLeading: 0,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: 6
          )
        )
        .stroke(Theme.Palette.line, lineWidth: 1)
      )
    )
    .clipShape(
      UnevenRoundedRectangle(
        cornerRadii: .init(
          topLeading: 0,
          bottomLeading: 0,
          bottomTrailing: 0,
          topTrailing: 6
        )
      )
    )
    .overlay(alignment: .topTrailing) {
      // Edit/Check button in top right corner
      Button(action: {}) {
        Image(systemName: "checkmark")
          .font(.system(size: 8))
          .foregroundColor(Theme.Palette.ink)
          .frame(width: 8, height: 8)
      }
      .buttonStyle(.plain)
      .padding(6)
      .background(
        Theme.Palette.surface.opacity(0.8)
          .background(.ultraThinMaterial)
      )
      .clipShape(
        UnevenRoundedRectangle(
          cornerRadii: .init(
            topLeading: 0,
            bottomLeading: 6,
            bottomTrailing: 0,
            topTrailing: 6
          )
        )
      )
      .overlay(
        UnevenRoundedRectangle(
          cornerRadii: .init(
            topLeading: 0,
            bottomLeading: 6,
            bottomTrailing: 0,
            topTrailing: 6
          )
        )
        .stroke(Theme.Palette.line, lineWidth: 1)
      )
      .offset(x: -8, y: 8)
    }
  }

  private func isCategorySelected(_ category: TimelineCategory) -> Bool {
    let currentNormalized = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let categoryNormalized = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return currentNormalized == categoryNormalized
  }
}

struct CategoryPill: View {
  let category: TimelineCategory
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 4) {
        // Colored dot
        Circle()
          .fill(categoryColor)
          .frame(width: 8, height: 8)

        // Category name - no line limit, text can wrap if needed
        Text(category.name)
          .font(Font.system(size: 10).weight(.medium))
          .foregroundColor(Theme.Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .lineLimit(nil)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(pillBackground)
      .cornerRadius(6)
      .overlay(
        Group {
          if category.isIdle && !isSelected {
            // Dotted border for Idle category
            RoundedRectangle(cornerRadius: 6)
              .inset(by: 0.375)
              .stroke(style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
              .foregroundColor(pillBorder)
          } else {
            RoundedRectangle(cornerRadius: 6)
              .inset(by: 0.375)
              .stroke(pillBorder, lineWidth: 0.75)
          }
        }
      )
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
  }

  private var categoryColor: Color {
    if let nsColor = NSColor(hex: category.colorHex) {
      return Color(nsColor: nsColor)
    }
    return Color.gray
  }

  private var pillBackground: some View {
    Group {
      if isSelected {
        // Gradient for selected state
        LinearGradient(
          colors: [
            Theme.Palette.inset,  // #fffdf8
            Theme.Palette.accentTint,  // #ffe8d3
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      } else {
        Theme.Palette.surface  // #fefefe
      }
    }
  }

  private var pillBorder: Color {
    if isSelected {
      return Theme.Palette.accentTint  // #fbbb80
    } else if category.isIdle {
      // Dotted border for Idle category
      return Theme.Palette.line  // Will be styled differently
    } else {
      return Theme.Palette.line  // #e1e1e1
    }
  }
}
