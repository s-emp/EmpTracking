import Cocoa

final class DetailCellView: NSTableCellView {
    private let colorDot = NSView()
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
        colorDot.translatesAutoresizingMaskIntoConstraints = false
        colorDot.wantsLayer = true
        colorDot.layer?.cornerRadius = 4
        addSubview(colorDot)

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
            colorDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            colorDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorDot.widthAnchor.constraint(equalToConstant: 8),
            colorDot.heightAnchor.constraint(equalToConstant: 8),

            iconView.leadingAnchor.constraint(equalTo: colorDot.trailingAnchor, constant: 4),
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

    func configure(log: ActivityLog, appInfo: AppInfo?, tag: Tag? = nil) {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        let duration = log.endTime.timeIntervalSince(log.startTime)
        let minutes = max(1, Int(duration) / 60)

        if log.isIdle {
            titleLabel.stringValue = "Idle"
            titleLabel.textColor = .tertiaryLabelColor
            iconView.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Idle")
            iconView.contentTintColor = .tertiaryLabelColor
            colorDot.isHidden = true
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

            if let tag = tag {
                colorDot.isHidden = false
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let hex = isDark ? tag.colorDark : tag.colorLight
                colorDot.layer?.backgroundColor = NSColor(hex: hex).cgColor

                // Overridden tag: show border to distinguish from app default
                if log.tagId != nil {
                    colorDot.layer?.borderWidth = 1.5
                    colorDot.layer?.borderColor = NSColor.labelColor.cgColor
                } else {
                    colorDot.layer?.borderWidth = 0
                }
            } else {
                colorDot.isHidden = true
                colorDot.layer?.borderWidth = 0
            }
        }

        let start = timeFmt.string(from: log.startTime)
        let end = timeFmt.string(from: log.endTime)
        timeLabel.stringValue = "\(start) \u{2013} \(end) (\(minutes)\u{043C}\u{0438}\u{043D})"
    }

    func configure(remoteLog log: RemoteLog) {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        let duration = log.endTime.timeIntervalSince(log.startTime)
        let minutes = max(1, Int(duration) / 60)

        if log.isIdle {
            titleLabel.stringValue = "Idle (\(log.deviceName))"
            titleLabel.textColor = .tertiaryLabelColor
            iconView.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Idle")
            iconView.contentTintColor = .tertiaryLabelColor
            colorDot.isHidden = true
        } else {
            let appName = log.appName
            if let windowTitle = log.windowTitle, !windowTitle.isEmpty {
                titleLabel.stringValue = "\(appName) \u{2014} \(windowTitle)"
            } else {
                titleLabel.stringValue = appName
            }
            titleLabel.textColor = .labelColor
            iconView.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Remote")
            iconView.contentTintColor = .secondaryLabelColor
            colorDot.isHidden = true
            colorDot.layer?.borderWidth = 0
        }

        let start = timeFmt.string(from: log.startTime)
        let end = timeFmt.string(from: log.endTime)
        timeLabel.stringValue = "\(log.deviceName) \u{00B7} \(start) \u{2013} \(end) (\(minutes)\u{043C}\u{0438}\u{043D})"
    }
}
