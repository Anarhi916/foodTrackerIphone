import SwiftUI
import UIKit

// Design tokens mirroring Android's Material 3 tonal palette (ui/theme/Color.kt).
// Roles are adaptive (light/dark) via a UIColor dynamic provider — dark mode on iOS
// keeps working and matches the Android md_dark_* scheme.
//
// Role mapping Android -> iOS:
//   md_primary               -> AppColor.primary            (#1B9E3E)
//   md_primaryContainer      -> AppColor.primaryContainer   (#C8F0CF)
//   md_background/surface    -> AppColor.background/surface (#F6FBF4)
//   md_surfaceVariant        -> AppColor.surfaceVariant     (#DCE5DB) — input fields, progress track
//   md_surfaceContainer      -> AppColor.surfaceContainer   (#EBF1E9) — regular card
//   md_surfaceContainerHigh  -> AppColor.surfaceContainerHigh(#E5EBE3) — elevated card
//   md_onSurface             -> AppColor.onSurface          (#181D18)
//   md_onSurfaceVariant      -> AppColor.onSurfaceVariant   (#404942) — secondary text
//   md_outline / Variant     -> AppColor.outline / outlineVariant

private func dyn(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
    })
}

// sRGB variant. Saturated brand colors (the app-bar green) must render in sRGB to match
// the Android app exactly — Android draws #1B9E3E in sRGB → (27,158,62); interpreting the
// same hex as Display-P3 would shift it to a brighter (0,161,45).
private func dynSRGB(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(srgb: dark) : UIColor(srgb: light)
    })
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            displayP3Red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    convenience init(srgb: UInt32) {
        self.init(
            red: Double((srgb >> 16) & 0xFF) / 255.0,
            green: Double((srgb >> 8) & 0xFF) / 255.0,
            blue: Double(srgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

enum AppColor {
    // Brand / primary — rendered in sRGB (not Display-P3) so the saturated app-bar green
    // lands on Android's exact rendered (27,158,62). Same #1B9E3E hex, matching color space.
    static let primary            = dynSRGB(light: 0x1B9E3E, dark: 0x8DD996)
    static let onPrimary          = dyn(light: 0xFFFFFF, dark: 0x00390F)
    static let primaryContainer   = dyn(light: 0xC8F0CF, dark: 0x00531A)
    static let onPrimaryContainer = dyn(light: 0x00390F, dark: 0xC8F0CF)

    // Secondary (used for the table "Total" row, like md_secondaryContainer)
    static let secondaryContainer   = dyn(light: 0xD1E8D5, dark: 0x354B3B)
    static let onSecondaryContainer = dyn(light: 0x0C1F13, dark: 0xD1E8D5)

    // Backgrounds / surfaces
    static let background            = dyn(light: 0xF6FBF4, dark: 0x101510)
    static let surface               = dyn(light: 0xF6FBF4, dark: 0x101510)
    static let surfaceVariant        = dyn(light: 0xDCE5DB, dark: 0x404942)
    static let surfaceContainer      = dyn(light: 0xEBF1E9, dark: 0x1C211C)
    static let surfaceContainerHigh  = dyn(light: 0xE5EBE3, dark: 0x262B25)
    // Neutral tonal card fill — matches the Android app's rendered card color (#DCE5DB).
    static let surfaceContainerHighest = dyn(light: 0xDCE5DB, dark: 0x3B443D)

    // On-colors
    static let onSurface        = dyn(light: 0x181D18, dark: 0xDFE4DB)
    static let onSurfaceVariant = dyn(light: 0x404942, dark: 0xC0C9BF)

    // Disabled state of a filled button (like Material 3: onSurface over surface).
    // Noticeably darker than the section background so the button outline is visible.
    static let disabledContainer = dyn(light: 0xBAC3B9, dark: 0x282D27)
    static let onDisabled        = dyn(light: 0x6A736C, dark: 0x8A938B)

    // Outlines
    static let outline        = dyn(light: 0x707972, dark: 0x8A938B)
    static let outlineVariant = dyn(light: 0xC0C9BF, dark: 0x404942)

    // Nutrient progress bars (semantics like ProgressGreen/Yellow/… on Android)
    static let progressGreen  = dyn(light: 0x2E9E34, dark: 0x5FCF66)
    static let progressYellow = dyn(light: 0xF5B700, dark: 0xF5C842)
    static let progressOrange = dyn(light: 0xF57C00, dark: 0xFF9A3D)
    static let progressRed    = dyn(light: 0xE53935, dark: 0xFF6B67)
}

// Unified corner-radius scale (matches AppShapes on Android).
enum AppRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16   // cards
    static let large: CGFloat = 20    // large containers
    static let extraLarge: CGFloat = 28
}

// MARK: - Typography (Roboto — same font family as the Android app)
//
// The Android app renders in the system Roboto face. To match it 1:1 on iOS we bundle
// Roboto (see Fonts/ + UIAppFonts in Info.plist) and route every text role through here.
// Sizes equal the default point sizes of the matching iOS text styles, and each token is
// built with `relativeTo:` so Dynamic Type still scales the text like the system fonts did.
// Weights map onto Android's Material 3 type scale (Regular 400 / Medium 500 / SemiBold 600).
enum AppFont {
    enum Weight {
        case regular, medium, semibold, bold
        var psName: String {
            switch self {
            case .regular:  return "Roboto-Regular"
            case .medium:   return "Roboto-Medium"
            case .semibold: return "Roboto-SemiBold"
            case .bold:     return "Roboto-Bold"
            }
        }
    }

    static func roboto(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(weight.psName, size: size, relativeTo: style)
    }

    // Semantic roles used across the UI.
    static let body            = roboto(17, .regular,  relativeTo: .body)
    static let headline        = roboto(17, .semibold, relativeTo: .headline)   // section headers, dialog titles
    static let subheadline     = roboto(15, .regular,  relativeTo: .subheadline)
    static let subheadlineBold = roboto(15, .semibold, relativeTo: .subheadline)
    static let callout         = roboto(16, .regular,  relativeTo: .callout)
    static let calloutBold     = roboto(16, .semibold, relativeTo: .callout)
    static let caption         = roboto(12, .regular,  relativeTo: .caption)
    static let captionBold     = roboto(12, .medium,   relativeTo: .caption)    // table header / totals cells
    static let caption2        = roboto(11, .regular,  relativeTo: .caption2)
    // Card / section titles — pinned to Android's EXACT sp. The app forces Dynamic Type to
    // .xLarge app-wide, which would scale a relativeTo title ~12% ABOVE Android; fixedSize
    // keeps these 1:1 with the Android Material type scale instead.
    static let cardTitle       = Font.custom("Roboto-SemiBold", fixedSize: 22)  // headlineMedium — "Сегодня", "БЖУ и Калории"
    static let sectionHeader   = Font.custom("Roboto-SemiBold", fixedSize: 16)  // titleMedium+SemiBold — collapsible Vitamins/Minerals/Fat headers
}

// MARK: - Card style

extension View {
    /// Standard tonal card: medium (16) corner radius, given surface, soft shadow.
    /// Defaults to surfaceVariant (#DCE5DB) — matches the section background on Android.
    func cardStyle(
        _ container: Color = AppColor.surfaceContainerHighest,
        radius: CGFloat = AppRadius.medium,
        elevation: CGFloat = 1
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(container)
                .shadow(
                    color: .black.opacity(elevation > 0 ? 0.06 * Double(elevation) : 0),
                    radius: elevation * 2,
                    y: elevation
                )
        )
    }

    /// Soft styling for a modal sheet's toolbar: light nav bar background + brand-green
    /// text buttons. Without the global green and without the heavy dark iOS 26 "capsules".
    func sheetChrome() -> some View {
        self
            .toolbarBackground(AppColor.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(AppColor.primary)
    }
}
