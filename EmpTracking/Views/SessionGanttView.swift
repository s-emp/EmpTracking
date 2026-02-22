import SwiftUI
import Charts

struct GanttEntry: Identifiable {
    let id = UUID()
    let appName: String
    let startTime: Date
    let endTime: Date
    let colorIndex: Int
}

struct SessionGanttView: View {
    let entries: [GanttEntry]

    /// Apps sorted by total duration (most active first), max 15.
    private var sortedAppNames: [String] {
        var totals: [String: TimeInterval] = [:]
        for entry in entries {
            totals[entry.appName, default: 0] += entry.endTime.timeIntervalSince(entry.startTime)
        }
        return totals.sorted { $0.value > $1.value }
            .prefix(15)
            .map { $0.key }
    }

    /// X-axis domain: first session start rounded down to hour, last session end rounded up to hour.
    private var timeDomain: ClosedRange<Date> {
        guard let earliest = entries.map(\.startTime).min(),
              let latest = entries.map(\.endTime).max() else {
            let now = Date()
            return now...now.addingTimeInterval(3600)
        }
        let cal = Calendar.current
        let startHour = cal.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        let endComponents = cal.dateComponents([.year, .month, .day, .hour], from: latest)
        var endHour = cal.date(from: endComponents) ?? latest
        if endHour < latest {
            endHour = cal.date(byAdding: .hour, value: 1, to: endHour) ?? latest
        }
        if endHour <= startHour {
            return startHour...startHour.addingTimeInterval(3600)
        }
        return startHour...endHour
    }

    var body: some View {
        let visibleApps = Set(sortedAppNames)
        let visibleEntries = entries.filter { visibleApps.contains($0.appName) }

        Chart(visibleEntries) { entry in
            RectangleMark(
                xStart: .value("Start", entry.startTime),
                xEnd: .value("End", entry.endTime),
                y: .value("App", entry.appName)
            )
            .foregroundStyle(GanttColorPalette.colors[entry.colorIndex % GanttColorPalette.colors.count])
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: sortedAppNames)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)), centered: false)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
    }
}
