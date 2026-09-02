import SwiftUI

struct HistoryScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedDates: Set<String> = []
    @State private var allDates: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(
                String(localized: "История"),
                leading: {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    }
                }
            )
            ScrollView {
                VStack(spacing: 12) {
                    if allDates.isEmpty {
                        Text("Нет данных")
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(allDates, id: \.self) { date in
                            dayCard(for: date)
                        }
                    }
                }
                .padding()
            }
            .background(AppColor.background)
        }
        .navigationBarHidden(true)
        .onAppear { allDates = NutritionRepository.shared.getAllDates() }
    }

    private func dayCard(for date: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation {
                    if expandedDates.contains(date) {
                        expandedDates.remove(date)
                    } else {
                        expandedDates.insert(date)
                    }
                }
            }) {
                HStack {
                    Text(formatDate(date))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expandedDates.contains(date) ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }

            if expandedDates.contains(date) {
                let entries = viewModel.getEntriesForDate(date)
                if entries.isEmpty {
                    Text("Нет записей")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let totals = entries.reduce(NutrientData()) { acc, entry in
                        acc + viewModel.parseNutrients(entry.nutrientsJson)
                    }

                    // Summary chips
                    HStack(spacing: 8) {
                        summaryChip(String(localized: "Ккал"), value: String(format: "%.0f", totals.calories))
                        summaryChip(String(localized: "Б"), value: String(format: "%.1f %@", totals.protein, String(localized: "г")))
                        summaryChip(String(localized: "Ж"), value: String(format: "%.1f %@", totals.fat, String(localized: "г")))
                        summaryChip(String(localized: "У"), value: String(format: "%.1f %@", totals.carbs, String(localized: "г")))
                    }

                    // Entry list
                    ForEach(entries, id: \.self) { entry in
                        let nutrients = viewModel.parseNutrients(entry.nutrientsJson)
                        HStack {
                            Text(entry.foodName).font(.caption).lineLimit(2)
                            Spacer()
                            Text(WeightFormat.short(grams: entry.weightGrams)).font(.caption2).foregroundColor(.secondary)
                            Text("\(Int(nutrients.calories)) \(String(localized: "ккал"))").font(.caption2)
                        }
                    }

                    // Progress bars for macros + fat details
                    if let norms = viewModel.dailyNorms {
                        Divider()
                        let bars: [(name: String, value: Double, target: Double, unit: String, upperRatio: Double)] = [
                            (String(localized: "Калории"), totals.calories, norms.calories, String(localized: "ккал"), 1.5),
                            (String(localized: "Белки"), totals.protein, norms.protein, String(localized: "г"), 1.5),
                            (String(localized: "Жиры"), totals.fat, norms.fat, String(localized: "г"), 1.5),
                            (String(localized: "Углеводы"), totals.carbs, norms.carbs, String(localized: "г"), 1.5),
                            (String(localized: "Клетчатка"), totals.fiber, norms.fiber, String(localized: "г"), 1.5),
                            (String(localized: "Насыщ. жиры"), totals.saturatedFat, norms.saturatedFat, String(localized: "г"), 1.0),
                            (String(localized: "Мононенасыщ."), totals.monounsaturatedFat, norms.monounsaturatedFat, String(localized: "г"), 3.0),
                            (String(localized: "Полиненасыщ."), totals.polyunsaturatedFat, norms.polyunsaturatedFat, String(localized: "г"), 3.0),
                            (String(localized: "Холестерин"), totals.cholesterol, norms.cholesterol, String(localized: "мг"), 1.3)
                        ]
                        ForEach(bars, id: \.name) { bar in
                            historyProgressBar(name: bar.name, value: bar.value, target: bar.target, unit: bar.unit, upperRatio: bar.upperRatio)
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func summaryChip(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption).bold()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppColor.surfaceVariant))
    }

    private func historyProgressBar(name: String, value: Double, target: Double, unit: String, upperRatio: Double) -> some View {
        let pct = target > 0 ? value / target : 0
        let color: Color = {
            if pct > upperRatio * 1.3 { return AppColor.progressRed }
            if pct > upperRatio { return AppColor.progressOrange }
            if pct >= 0.8 { return AppColor.progressGreen }
            if pct >= 0.4 { return AppColor.progressYellow }
            return AppColor.progressRed
        }()
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.caption2)
                Spacer()
                Text(String(format: "%.1f / %.1f %@ (%d%%)", value, target, unit, Int(pct * 100)))
                    .font(.caption2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(AppColor.surfaceVariant).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: min(CGFloat(pct) * geo.size.width, geo.size.width), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Сегодня") }
        if calendar.isDateInYesterday(date) { return String(localized: "Вчера") }

        let display = DateFormatter()
        display.locale = .current
        display.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return display.string(from: date)
    }
}
