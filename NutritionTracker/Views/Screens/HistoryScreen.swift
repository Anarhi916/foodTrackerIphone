import SwiftUI

struct HistoryScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var expandedDates: Set<String> = []
    @State private var allDates: [String] = []

    var body: some View {
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
        .background(Color(.systemGray6))
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
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
                        summaryChip("Ккал", value: "\(Int(totals.calories))")
                        summaryChip("Б", value: String(format: "%.0f", totals.protein))
                        summaryChip("Ж", value: String(format: "%.0f", totals.fat))
                        summaryChip("У", value: String(format: "%.0f", totals.carbs))
                    }

                    // Entry list
                    ForEach(entries, id: \.self) { entry in
                        let nutrients = viewModel.parseNutrients(entry.nutrientsJson)
                        HStack {
                            Text(entry.foodName).font(.caption).lineLimit(2)
                            Spacer()
                            Text("\(Int(entry.weightGrams))г").font(.caption2).foregroundColor(.secondary)
                            Text("\(Int(nutrients.calories)) ккал").font(.caption2)
                        }
                    }

                    // Progress bars for macros
                    if let norms = viewModel.dailyNorms {
                        Divider()
                        let macros: [(String, Double, Double)] = [
                            ("Калории", totals.calories, norms.calories),
                            ("Белки", totals.protein, norms.protein),
                            ("Жиры", totals.fat, norms.fat),
                            ("Углеводы", totals.carbs, norms.carbs)
                        ]
                        ForEach(macros, id: \.0) { name, value, target in
                            historyProgressBar(name: name, value: value, target: target)
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
    }

    private func summaryChip(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption).bold()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray4).opacity(0.5)))
    }

    private func historyProgressBar(name: String, value: Double, target: Double) -> some View {
        let pct = target > 0 ? value / target : 0
        let color: Color = pct > 1.3 ? .red : pct >= 0.8 ? .green : pct >= 0.4 ? .yellow : .red
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.caption2)
                Spacer()
                Text(String(format: "%.0f / %.0f (%d%%)", value, target, Int(pct * 100)))
                    .font(.caption2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray4)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: min(CGFloat(pct) * geo.size.width, geo.size.width), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }

        let display = DateFormatter()
        display.dateFormat = "dd.MM.yyyy"
        return display.string(from: date)
    }
}
