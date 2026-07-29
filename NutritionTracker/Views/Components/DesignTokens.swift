import SwiftUI
import UIKit

// Design-токены, зеркалящие Material 3 tonal-палитру Android (ui/theme/Color.kt).
// Роли адаптивные (light/dark) через UIColor dynamic provider — dark-режим на iOS
// продолжает работать и совпадает с Android md_dark_* схемой.
//
// Соответствие ролей Android → iOS:
//   md_primary               → AppColor.primary            (#1B9E3E)
//   md_primaryContainer      → AppColor.primaryContainer   (#C8F0CF)
//   md_background/surface    → AppColor.background/surface (#F6FBF4)
//   md_surfaceVariant        → AppColor.surfaceVariant     (#DCE5DB) — поля ввода, дорожка прогресса
//   md_surfaceContainer      → AppColor.surfaceContainer   (#EBF1E9) — обычная карточка
//   md_surfaceContainerHigh  → AppColor.surfaceContainerHigh(#E5EBE3) — приподнятая карточка
//   md_onSurface             → AppColor.onSurface          (#181D18)
//   md_onSurfaceVariant      → AppColor.onSurfaceVariant   (#404942) — вторичный текст
//   md_outline / Variant     → AppColor.outline / outlineVariant

private func dyn(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
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
}

enum AppColor {
    // Brand / primary
    static let primary            = dyn(light: 0x1B9E3E, dark: 0x8DD996)
    static let onPrimary          = dyn(light: 0xFFFFFF, dark: 0x00390F)
    static let primaryContainer   = dyn(light: 0xC8F0CF, dark: 0x00531A)
    static let onPrimaryContainer = dyn(light: 0x00390F, dark: 0xC8F0CF)

    // Secondary (используется для «Итого»-строки таблицы, как md_secondaryContainer)
    static let secondaryContainer   = dyn(light: 0xD1E8D5, dark: 0x354B3B)
    static let onSecondaryContainer = dyn(light: 0x0C1F13, dark: 0xD1E8D5)

    // Backgrounds / surfaces
    static let background            = dyn(light: 0xF6FBF4, dark: 0x101510)
    static let surface               = dyn(light: 0xF6FBF4, dark: 0x101510)
    static let surfaceVariant        = dyn(light: 0xDCE5DB, dark: 0x404942)
    static let surfaceContainer      = dyn(light: 0xEBF1E9, dark: 0x1C211C)
    static let surfaceContainerHigh  = dyn(light: 0xE5EBE3, dark: 0x262B25)

    // On-colors
    static let onSurface        = dyn(light: 0x181D18, dark: 0xDFE4DB)
    static let onSurfaceVariant = dyn(light: 0x404942, dark: 0xC0C9BF)

    // Disabled-состояние filled-кнопки (как Material 3: onSurface поверх surface).
    // Заметно темнее фона секции, чтобы виден контур кнопки.
    static let disabledContainer = dyn(light: 0xC4CDC3, dark: 0x2A2F29)
    static let onDisabled        = dyn(light: 0x6A736C, dark: 0x8A938B)

    // Outlines
    static let outline        = dyn(light: 0x707972, dark: 0x8A938B)
    static let outlineVariant = dyn(light: 0xC0C9BF, dark: 0x404942)

    // Прогресс-бары нутриентов (семантика, как ProgressGreen/Yellow/… на Android)
    static let progressGreen  = dyn(light: 0x2E9E34, dark: 0x5FCF66)
    static let progressYellow = dyn(light: 0xF5B700, dark: 0xF5C842)
    static let progressOrange = dyn(light: 0xF57C00, dark: 0xFF9A3D)
    static let progressRed    = dyn(light: 0xE53935, dark: 0xFF6B67)
}

// Единая шкала скруглений (совпадает с AppShapes на Android).
enum AppRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16   // карточки
    static let large: CGFloat = 20    // крупные контейнеры
    static let extraLarge: CGFloat = 28
}

// MARK: - Card style

extension View {
    /// Стандартная tonal-карточка: скругление medium (16), заданная поверхность, мягкая тень.
    /// По умолчанию surfaceVariant (#DCE5DB) — совпадает с фоном секций на Android.
    func cardStyle(
        _ container: Color = AppColor.surfaceVariant,
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

    /// Мягкое оформление тулбара модального листа: светлый фон навбара + бренд-зелёные
    /// текст-кнопки. Без глобального зелёного и без тяжёлых тёмных «капсул» iOS 26.
    func sheetChrome() -> some View {
        self
            .toolbarBackground(AppColor.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(AppColor.primary)
    }
}
