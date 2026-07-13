import SwiftUI

enum StatPeriod: String, CaseIterable {
    case week
    case month
    case custom

    var displayName: String {
        switch self {
        case .week: return String(localized: "Неделя")
        case .month: return String(localized: "Месяц")
        case .custom: return String(localized: "Свой период")
        }
    }
}

struct StatisticsScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var selectedPeriod: StatPeriod = .week
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var endDate = Date()
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var totals: NutrientData?
    @State private var numDays: Int = 7
    @State private var isLoading = false
    @State private var csvShareItem: CSVShareItem?

    private let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return f
    }()

    private var effectiveStart: Date {
        switch selectedPeriod {
        case .week: return Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        case .month: return Calendar.current.date(byAdding: .day, value: -29, to: Date())!
        case .custom: return startDate
        }
    }

    private var effectiveEnd: Date {
        switch selectedPeriod {
        case .week, .month: return Date()
        case .custom: return endDate
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Period selector card
                periodCard

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if let t = totals {
                    let normForPeriod = viewModel.dailyNorms.map { $0 * Double(numDays) }
                    NutrientStatCard(title: String(localized: "БЖУ и Калории"), items: t.macrosList(), normItems: normForPeriod?.macrosList())
                    NutrientStatCard(title: String(localized: "Витамины"), items: t.vitaminsList(), normItems: normForPeriod?.vitaminsList())
                    NutrientStatCard(title: String(localized: "Минералы и микроэлементы"), items: t.mineralsList(), normItems: normForPeriod?.mineralsList())
                    NutrientStatCard(title: String(localized: "Жиры (детально)"), items: t.fatDetailsList(), normItems: normForPeriod?.fatDetailsList())
                }
            }
            .padding(16)
        }
        .background(Color(.systemGray6))
        .navigationTitle("Статистика")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadData() }
        .onChange(of: selectedPeriod) { _ in loadData() }
        .onChange(of: startDate) { _ in if selectedPeriod == .custom { loadData() } }
        .onChange(of: endDate) { _ in if selectedPeriod == .custom { loadData() } }
        .sheet(isPresented: $showStartPicker) {
            DatePickerSheet(title: "Начало периода", date: $startDate) {
                if startDate > endDate { endDate = startDate }
                showStartPicker = false
                loadData()
            }
        }
        .sheet(isPresented: $showEndPicker) {
            DatePickerSheet(title: "Конец периода", date: $endDate) {
                if endDate < startDate { startDate = endDate }
                showEndPicker = false
                loadData()
            }
        }
        .sheet(item: $csvShareItem) { item in
            ActivityView(items: [item.url])
        }
    }

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Период").font(.headline).bold()

            Picker("", selection: $selectedPeriod) {
                ForEach(StatPeriod.allCases, id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.segmented)

            if selectedPeriod == .custom {
                HStack(spacing: 8) {
                    Button { showStartPicker = true } label: {
                        Label(displayFormatter.string(from: startDate), systemImage: "calendar")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button { showEndPicker = true } label: {
                        Label(displayFormatter.string(from: endDate), systemImage: "calendar")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("\(displayFormatter.string(from: effectiveStart)) — \(displayFormatter.string(from: effectiveEnd)) \(String(format: String(localized: "(%lld дн.)"), numDays))")
                .font(.caption)
                .foregroundColor(.secondary)

            Button { exportCSV() } label: {
                Label("Экспорт в Excel", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)))
    }

    private func exportCSV() {
        let start = isoFormatter.string(from: effectiveStart)
        let end = isoFormatter.string(from: effectiveEnd)
        let entries = NutritionRepository.shared.getEntriesForDateRange(start: start, end: end)
            .sorted { $0.date < $1.date }

        var csv = "\u{FEFF}"
        csv += String(localized: "Дата,Продукт,Вес (г)") + "\n"
        var lastDate = ""
        for entry in entries {
            if !lastDate.isEmpty && entry.date != lastDate {
                csv += "\(entry.date),,\n"
            }
            lastDate = entry.date
            let escapedName = entry.foodName.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(entry.date),\"\(escapedName)\",\(Int(entry.weightGrams))\n"
        }

        let fileName = "nutrition_\(start)_\(end).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.data(using: .utf8)?.write(to: url)
            csvShareItem = CSVShareItem(url: url)
        } catch {
            // Silently ignore — nothing to share if the file can't be written
        }
    }

    private func loadData() {
        isLoading = true
        let start = isoFormatter.string(from: effectiveStart)
        let end = isoFormatter.string(from: effectiveEnd)
        let entries = NutritionRepository.shared.getEntriesForDateRange(start: start, end: end)
        let distinctDates = Set(entries.map { $0.date }).count
        numDays = max(distinctDates, 1)
        totals = entries.reduce(NutrientData()) { acc, entry in
            acc + viewModel.parseNutrients(entry.nutrientsJson)
        }
        isLoading = false
    }
}

// MARK: - Nutrient Stat Card

private struct NutrientStatCard: View {
    let title: String
    let items: [(key: String, name: String, value: Double)]
    let normItems: [(key: String, name: String, value: Double)]?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).bold()

            // Header
            HStack {
                Text("Нутриент").font(.caption2).bold().frame(maxWidth: .infinity, alignment: .leading)
                Text("Факт").font(.caption2).bold().frame(width: 60, alignment: .trailing)
                if normItems != nil {
                    Text("Норма").font(.caption2).bold().frame(width: 60, alignment: .trailing)
                    Text("%").font(.caption2).bold().frame(width: 40, alignment: .trailing)
                }
            }
            Divider()

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let normValue = normItems?.indices.contains(index) == true ? normItems![index].value : nil
                let pct: Int? = {
                    guard let nv = normValue, nv > 0 else { return nil }
                    return Int(item.value / nv * 100)
                }()
                let pctColor: Color = {
                    guard let p = pct else { return .primary }
                    if p >= 90 { return .green }
                    if p >= 50 { return .primary }
                    return .red
                }()

                HStack {
                    Text(item.name).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatNutrientValue(item.value)).font(.caption).bold().frame(width: 60, alignment: .trailing)
                    if normItems != nil {
                        Text(formatNutrientValue(normValue ?? 0)).font(.caption).frame(width: 60, alignment: .trailing)
                        Text(pct != nil ? "\(pct!)%" : "—").font(.caption).bold().foregroundColor(pctColor).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)))
    }

    private func formatNutrientValue(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 1 { return String(format: "%.1f", value) }
        if value > 0 { return String(format: "%.2f", value) }
        return "0"
    }
}

// MARK: - Date Picker Sheet

private struct DatePickerSheet: View {
    let title: String
    @Binding var date: Date
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { onDone() }
                    }
                }
        }
    }
}

// MARK: - CSV Share

private struct CSVShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
