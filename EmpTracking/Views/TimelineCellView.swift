import Cocoa

final class TimelineCellView: NSTableCellView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let durationLabel = NSTextField(labelWithString: "")

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
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .systemFont(ofSize: 13)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(durationLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(summary: AppSummary) {
        titleLabel.stringValue = summary.appName
        titleLabel.textColor = .labelColor
        iconView.image = summary.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")

        let total = Int(summary.totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            durationLabel.stringValue = "\(hours)ч \(minutes)мин"
        } else {
            durationLabel.stringValue = "\(minutes)мин"
        }
    }
}
