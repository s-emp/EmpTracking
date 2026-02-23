import Cocoa
import EmpUI_macOS

final class TimelineCellView: NSTableCellView {

    private let iconView = EmpImage()
    private let titleLabel = EmpText()
    private let durationLabel = EmpText()
    private let progressBar = EmpProgressBar()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(durationLabel)
        addSubview(progressBar)

        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            // Title — top row
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            // Duration — right-aligned, same line as title
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            // Progress bar — below title
            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            progressBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            progressBar.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            // Icon — spans from title top to progress bar bottom, 1:1 aspect ratio
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            iconView.widthAnchor.constraint(equalTo: iconView.heightAnchor),
        ])
    }

    func configure(summary: AppSummary, totalDuration: TimeInterval) {
        let icon = summary.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")!
        iconView.configure(with: EmpImage.ViewModel(
            common: CommonViewModel(corners: .init(radius: 8)),
            image: icon,
            size: CGSize(width: 28, height: 28),
            contentMode: .aspectFit
        ))

        // Deactivate EmpImage's internal fixed size constraints so external layout drives sizing
        for subview in iconView.subviews {
            for constraint in subview.constraints where constraint.secondAttribute == .notAnAttribute {
                if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                    constraint.isActive = false
                }
            }
        }

        titleLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: summary.appName,
                font: .systemFont(ofSize: 13, weight: .medium),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1
        ))

        let durationText = Self.formatDuration(summary.totalDuration)
        durationLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: durationText,
                font: .systemFont(ofSize: 13),
                color: NSColor.Semantic.textSecondary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        let progress: CGFloat = totalDuration > 0
            ? CGFloat(summary.totalDuration / totalDuration)
            : 0
        progressBar.configure(with: EmpProgressBar.ViewModel(
            progress: progress,
            fillColor: NSColor.Semantic.actionPrimary,
            barHeight: 3
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
