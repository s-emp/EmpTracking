import Cocoa

final class TimelineCellView: NSTableCellView {

    // MARK: - DS Components

    private let iconView = EmpImage()
    private let titleLabel = EmpText()
    private let durationLabel = EmpText()
    private let progressBar = EmpProgressBar()

    // MARK: - Separator

    private let separator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Setup

    private func setupViews() {
        let horizontalPadding = EmpSpacing.m.rawValue   // 16
        let topPadding = EmpSpacing.s.rawValue           // 12
        let iconTextGap = EmpSpacing.s.rawValue          // 12
        let rowProgressGap = EmpSpacing.xs.rawValue      // 8

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(durationLabel)
        addSubview(progressBar)
        addSubview(separator)

        // Duration label should not compress; title should truncate instead.
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            // Icon — top-left, 28x28
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            // Title — to the right of the icon
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: iconTextGap),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -EmpSpacing.xs.rawValue),

            // Duration — right-aligned
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            durationLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            // Progress bar — full width below the icon/text row
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            progressBar.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: rowProgressGap),

            // Separator — bottom edge, 1pt
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: topPadding),
            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        separator.layer?.backgroundColor = NSColor.Semantic.borderSubtle.cgColor
    }

    // MARK: - Configure

    func configure(summary: AppSummary, totalDuration: TimeInterval) {
        // Icon
        let icon = summary.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")!
        iconView.configure(with: EmpImage.ViewModel(
            common: CommonViewModel(corners: .init(radius: 8)),
            image: icon,
            size: CGSize(width: 28, height: 28),
            contentMode: .aspectFit
        ))

        // Title
        titleLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: summary.appName,
                font: .systemFont(ofSize: 14, weight: .medium),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1
        ))

        // Duration
        let durationText = Self.formatDuration(summary.totalDuration)
        durationLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: durationText,
                font: .systemFont(ofSize: 14, weight: .regular),
                color: NSColor.Semantic.textSecondary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        // Progress
        let progress: CGFloat = totalDuration > 0
            ? CGFloat(summary.totalDuration / totalDuration)
            : 0
        progressBar.configure(with: EmpProgressBar.ViewModel(
            progress: progress,
            fillColor: NSColor.Semantic.actionPrimary,
            barHeight: 4
        ))
    }

    /// Backward-compatible overload — will be removed in Task 2 when TimelineViewController is updated.
    @available(*, deprecated, message: "Use configure(summary:totalDuration:) instead")
    func configure(summary: AppSummary) {
        configure(summary: summary, totalDuration: 0)
    }

    // MARK: - Duration Formatting

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
