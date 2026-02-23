import Cocoa

final class TagCellView: NSTableCellView {
    private let colorDot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")

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
        colorDot.layer?.cornerRadius = 6
        addSubview(colorDot)

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
            colorDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            colorDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorDot.widthAnchor.constraint(equalToConstant: 12),
            colorDot.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: colorDot.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(summary: TagSummary) {
        if let tag = summary.tag {
            titleLabel.stringValue = tag.name
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? tag.colorDark : tag.colorLight
            colorDot.layer?.backgroundColor = NSColor(hex: hex).cgColor
        } else {
            titleLabel.stringValue = "Без тега"
            colorDot.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        }

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
