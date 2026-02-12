import Cocoa

final class DetailCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

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
        timeLabel.lineBreakMode = .byTruncatingTail
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            timeLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    func configure(log: ActivityLog, appInfo: AppInfo?) {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        let duration = log.endTime.timeIntervalSince(log.startTime)
        let minutes = max(1, Int(duration) / 60)

        if log.isIdle {
            titleLabel.stringValue = "Idle"
            titleLabel.textColor = .tertiaryLabelColor
            iconView.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Idle")
            iconView.contentTintColor = .tertiaryLabelColor
        } else {
            let appName = appInfo?.appName ?? "Unknown"
            if let windowTitle = log.windowTitle, !windowTitle.isEmpty {
                titleLabel.stringValue = "\(appName) — \(windowTitle)"
            } else {
                titleLabel.stringValue = appName
            }
            titleLabel.textColor = .labelColor
            iconView.image = appInfo?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")
            iconView.contentTintColor = nil
        }

        let start = timeFmt.string(from: log.startTime)
        let end = timeFmt.string(from: log.endTime)
        timeLabel.stringValue = "\(start) – \(end) (\(minutes)мин)"
    }
}
