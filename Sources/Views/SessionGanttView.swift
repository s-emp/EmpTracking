import SwiftUI
import Charts

struct GanttEntry: Identifiable {
    let id = UUID()
    let appName: String
    let startTime: Date
    let endTime: Date
    let colorIndex: Int
    let logIds: [Int64]
    let tagId: Int64?
}

struct SessionGanttView: View {
    let entries: [GanttEntry]
    var selectionState: GanttSelectionState?
    var tags: [Tag] = []

    /// Height per app row in the chart (ensures bars are at least ~8pt tall).
    private static let rowHeight: CGFloat = 28

    /// Apps sorted by total duration (most active first).
    private var sortedAppNames: [String] {
        var totals: [String: TimeInterval] = [:]
        for entry in entries {
            totals[entry.appName, default: 0] += entry.endTime.timeIntervalSince(entry.startTime)
        }
        return totals.sorted { $0.value > $1.value }
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
        let names = sortedAppNames
        let visibleApps = Set(names)
        let visibleEntries = entries.filter { visibleApps.contains($0.appName) }
        let chartHeight = CGFloat(names.count) * Self.rowHeight

        ScrollView(.vertical) {
            chart(visibleEntries: visibleEntries, names: names, chartHeight: chartHeight)
        }
    }

    private func chart(visibleEntries: [GanttEntry], names: [String], chartHeight: CGFloat) -> some View {
        Chart {
            entryMarks(visibleEntries)
            tagBorderMarks(visibleEntries)
            selectionMarks(visibleEntries)
            dragOverlayMark()
        }
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: names)
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
        .chartPlotStyle { plotArea in
            plotArea.frame(height: max(chartHeight, 100))
        }
        .chartOverlay { proxy in
            gestureOverlay(proxy: proxy)
        }
    }

    // MARK: - Chart Content

    @ChartContentBuilder
    private func entryMarks(_ visibleEntries: [GanttEntry]) -> some ChartContent {
        ForEach(visibleEntries) { entry in
            RectangleMark(
                xStart: .value("Start", entry.startTime),
                xEnd: .value("End", entry.endTime),
                y: .value("App", entry.appName)
            )
            .foregroundStyle(GanttColorPalette.colors[entry.colorIndex % GanttColorPalette.colors.count])
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .opacity(entryOpacity(entry))
        }
    }

    @ChartContentBuilder
    private func tagBorderMarks(_ visibleEntries: [GanttEntry]) -> some ChartContent {
        let tagged = visibleEntries.filter { $0.tagId != nil }
        ForEach(tagged) { entry in
            RectangleMark(
                xStart: .value("Start", entry.startTime),
                xEnd: .value("End", entry.endTime),
                y: .value("App", entry.appName)
            )
            .foregroundStyle(.clear)
            .annotation(position: .overlay) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(tagBorderColor(for: entry.tagId!) ?? .clear, lineWidth: 2)
            }
        }
    }

    @ChartContentBuilder
    private func selectionMarks(_ visibleEntries: [GanttEntry]) -> some ChartContent {
        if let state = selectionState {
            let selected = visibleEntries.filter { state.selectedEntryIds.contains($0.id) }
            ForEach(selected) { entry in
                RectangleMark(
                    xStart: .value("Start", entry.startTime),
                    xEnd: .value("End", entry.endTime),
                    y: .value("App", entry.appName)
                )
                .foregroundStyle(Color.accentColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    @ChartContentBuilder
    private func dragOverlayMark() -> some ChartContent {
        if let range = selectionState?.dragRange {
            RectangleMark(
                xStart: .value("Start", range.lowerBound),
                xEnd: .value("End", range.upperBound)
            )
            .foregroundStyle(Color.accentColor.opacity(0.1))
        }
    }

    // MARK: - Gesture Overlay

    private func gestureOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(dragGesture(proxy: proxy, geometry: geometry))
                .onTapGesture { location in
                    handleTap(at: location, proxy: proxy, geometry: geometry)
                }
        }
    }

    private func dragGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard let state = selectionState else { return }
                let origin = geometry[proxy.plotFrame].origin
                let startX = value.startLocation.x - origin.x
                let currentX = value.location.x - origin.x
                if let startDate = proxy.value(atX: startX) as Date?,
                   let currentDate = proxy.value(atX: currentX) as Date? {
                    state.dragStart = startDate
                    state.dragEnd = currentDate
                }
            }
            .onEnded { _ in
                guard let state = selectionState,
                      let range = state.dragRange else { return }
                let additive = NSEvent.modifierFlags.contains(.shift)
                state.selectOverlapping(entries: entries, range: range, additive: additive)
                state.dragStart = nil
                state.dragEnd = nil
            }
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let state = selectionState else { return }
        let origin = geometry[proxy.plotFrame].origin
        let x = location.x - origin.x
        guard let date = proxy.value(atX: x) as Date? else { return }

        let y = location.y - origin.y
        let appName = proxy.value(atY: y) as String?
        let additive = NSEvent.modifierFlags.contains(.shift)

        if let entry = entryAt(date: date, appName: appName) {
            if additive {
                state.toggle(entry.id)
            } else {
                state.selectedEntryIds = [entry.id]
            }
        } else if !additive {
            state.clear()
        }
    }

    // MARK: - Helpers

    private func entryAt(date: Date, appName: String?) -> GanttEntry? {
        entries.first { entry in
            entry.startTime <= date && date <= entry.endTime
                && (appName == nil || entry.appName == appName)
        }
    }

    private func entryOpacity(_ entry: GanttEntry) -> Double {
        guard let state = selectionState, state.hasSelection else { return 1.0 }
        return state.selectedEntryIds.contains(entry.id) ? 1.0 : 0.5
    }

    private func tagBorderColor(for tagId: Int64) -> Color? {
        guard let tag = tags.first(where: { $0.id == tagId }) else { return nil }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? tag.colorDark : tag.colorLight
        return Color(nsColor: NSColor(hex: hex))
    }
}
