import SwiftUI
import Charts

struct DonutChartEntry: Identifiable {
    let id = UUID()
    let appName: String
    let duration: TimeInterval
    let color: Color
    let icon: Image?
}

struct DonutChartView: View {
    let entries: [DonutChartEntry]

    /// Top 5 entries by duration for the legend.
    private var legendEntries: [DonutChartEntry] {
        Array(entries.sorted { $0.duration > $1.duration }.prefix(5))
    }

    /// Total duration across all entries (used to compute percentages).
    private var totalDuration: TimeInterval {
        entries.reduce(0) { $0 + $1.duration }
    }

    /// Entries with cumulative angles for icon placement.
    private var sectorAngles: [(entry: DonutChartEntry, midAngle: Angle)] {
        guard totalDuration > 0 else { return [] }
        var result: [(entry: DonutChartEntry, midAngle: Angle)] = []
        var cumulativeAngle: Double = 0
        for entry in entries {
            let fraction = entry.duration / totalDuration
            let sectorAngle = fraction * 360
            let mid = cumulativeAngle + sectorAngle / 2
            // Only show icon if sector is > 10% of total
            if fraction > 0.10 {
                result.append((entry: entry, midAngle: .degrees(mid - 90))) // offset by -90 because Charts starts at 12 o'clock
            }
            cumulativeAngle += sectorAngle
        }
        return result
    }

    var body: some View {
        VStack(spacing: 12) {
            // Donut chart with app icons
            Chart(entries) { entry in
                SectorMark(
                    angle: .value("Duration", entry.duration),
                    innerRadius: .ratio(0.6),
                    angularInset: 1
                )
                .cornerRadius(3)
                .foregroundStyle(entry.color)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .local)
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    let outerRadius = min(frame.width, frame.height) / 2
                    let innerRadius = outerRadius * 0.6
                    let midRadius = (innerRadius + outerRadius) / 2

                    ForEach(sectorAngles.indices, id: \.self) { index in
                        let item = sectorAngles[index]
                        let angle = item.midAngle
                        let x = center.x + midRadius * CGFloat(cos(angle.radians))
                        let y = center.y + midRadius * CGFloat(sin(angle.radians))
                        let iconSize: CGFloat = (outerRadius - innerRadius) * 0.6

                        if let icon = item.entry.icon {
                            icon
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: iconSize, height: iconSize)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .position(x: x, y: y)
                        }
                    }
                }
            }
            .frame(width: 136, height: 136)

            // Legend — top 5 entries
            VStack(alignment: .leading, spacing: 6) {
                ForEach(legendEntries) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 7, height: 7)

                        Text(entry.appName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Text(percentage(for: entry))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 16)
    }

    private func percentage(for entry: DonutChartEntry) -> String {
        guard totalDuration > 0 else { return "0%" }
        let pct = entry.duration / totalDuration * 100
        if pct < 1 {
            return "<1%"
        }
        return "\(Int(pct.rounded()))%"
    }
}
