import SwiftUI

/// In-app language picker that applies the new language instantly (no relaunch)
/// via `LocalizationManager`. Used on both onboarding and the profile screen.
struct LanguagePickerButton: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var showPicker = false

    private var currentLabel: String {
        let tag = localization.language
        if tag.isEmpty { return String(localized: "Системный") }
        return AppLocale.endonym(for: String(tag.prefix(2)))
    }

    var body: some View {
        Button(action: { showPicker = true }) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(currentLabel)
            }
            .font(.subheadline)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(AppColor.surfaceVariant))
        }
        .buttonStyle(.plain)
        .confirmationDialog(String(localized: "Язык"), isPresented: $showPicker, titleVisibility: .visible) {
            ForEach(AppLocale.supported, id: \.code) { lang in
                let label = lang.code.isEmpty ? String(localized: "Системный") : lang.endonym
                Button(label) {
                    localization.setLanguage(lang.code)
                }
            }
            Button(String(localized: "Отмена"), role: .cancel) {}
        }
    }
}
