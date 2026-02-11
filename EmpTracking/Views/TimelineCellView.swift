import Cocoa

final class TimelineCellView: NSTableCellView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let timeLabel = NSTextField(labelWithString: "")

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

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    func configure(appName: String, windowTitle: String?, startTime: Date, endTime: Date, icon: NSImage?, isIdle: Bool) {
        let title: String
        if isIdle {
            title = "Idle"
            titleLabel.textColor = .tertiaryLabelColor
        } else if let windowTitle = windowTitle, !windowTitle.isEmpty {
            title = "\(appName) — \(windowTitle)"
            titleLabel.textColor = .labelColor
        } else {
            title = appName
            titleLabel.textColor = .labelColor
        }
        titleLabel.stringValue = title

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let duration = Int(endTime.timeIntervalSince(startTime))
        let durationText: String
        if duration < 60 {
            durationText = "\(duration) сек"
        } else {
            durationText = "\(duration / 60) мин"
        }
        timeLabel.stringValue = "\(formatter.string(from: startTime)) – \(formatter.string(from: endTime))  (\(durationText))"

        if isIdle {
            iconView.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Idle")
        } else {
            iconView.image = icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")
        }
    }
}
