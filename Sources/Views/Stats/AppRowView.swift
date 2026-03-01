import Cocoa
import EmpUI_macOS
import SwiftUI

final class AppRowView: NSView {
    private let iconView = EmpImage()
    private let nameLabel = EmpText()
    private let timeLabel = EmpText()
    private let pctLabel = EmpText()
    private let progressBar = EmpProgressBar()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let views: [NSView] = [iconView, nameLabel, timeLabel, pctLabel, progressBar]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pctLabel.setContentHuggingPriority(.required, for: .horizontal)
        pctLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let padding = EmpSpacing.xs.rawValue

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: padding),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: padding),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            pctLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 5),
            pctLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            pctLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            pctLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),

            progressBar.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            progressBar.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    func configure(summary: AppSummary, totalDuration: TimeInterval, color: Color) {
        let icon = summary.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")!
        iconView.configure(with: EmpImage.ViewModel(
            common: CommonViewModel(corners: .init(radius: 6)),
            image: icon,
            size: CGSize(width: 26, height: 26),
            contentMode: .aspectFit
        ))

        nameLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: summary.appName,
                font: .systemFont(ofSize: 12.5, weight: .medium),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1
        ))

        timeLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: Self.formatDuration(summary.totalDuration),
                font: .systemFont(ofSize: 12.5, weight: .semibold),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        let pct = totalDuration > 0 ? Int(summary.totalDuration / totalDuration * 100) : 0
        pctLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: "\(pct)%",
                font: .systemFont(ofSize: 10.5),
                color: NSColor.Semantic.textTertiary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        let progress = totalDuration > 0 ? CGFloat(summary.totalDuration / totalDuration) : 0
        let nsColor = NSColor(color)
        progressBar.configure(with: EmpProgressBar.ViewModel(
            progress: progress,
            fillColor: nsColor,
            barHeight: 2.5
        ))
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}
