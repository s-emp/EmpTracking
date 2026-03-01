import Cocoa
import EmpUI_macOS

final class MetricsGridView: NSView {
    private let totalTimeCard = EmpInfoCard()
    private let activeTimeCard = EmpInfoCard()
    private let longestSessionCard = EmpInfoCard()
    private let appsUsedCard = EmpInfoCard()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let cards = [totalTimeCard, activeTimeCard, longestSessionCard, appsUsedCard]
        cards.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let gap = EmpSpacing.xs.rawValue

        NSLayoutConstraint.activate([
            // Row 1
            totalTimeCard.topAnchor.constraint(equalTo: topAnchor),
            totalTimeCard.leadingAnchor.constraint(equalTo: leadingAnchor),

            activeTimeCard.topAnchor.constraint(equalTo: topAnchor),
            activeTimeCard.leadingAnchor.constraint(equalTo: totalTimeCard.trailingAnchor, constant: gap),
            activeTimeCard.trailingAnchor.constraint(equalTo: trailingAnchor),
            activeTimeCard.widthAnchor.constraint(equalTo: totalTimeCard.widthAnchor),

            // Row 2
            longestSessionCard.topAnchor.constraint(equalTo: totalTimeCard.bottomAnchor, constant: gap),
            longestSessionCard.leadingAnchor.constraint(equalTo: leadingAnchor),
            longestSessionCard.bottomAnchor.constraint(equalTo: bottomAnchor),
            longestSessionCard.heightAnchor.constraint(equalTo: totalTimeCard.heightAnchor),

            appsUsedCard.topAnchor.constraint(equalTo: activeTimeCard.bottomAnchor, constant: gap),
            appsUsedCard.leadingAnchor.constraint(equalTo: longestSessionCard.trailingAnchor, constant: gap),
            appsUsedCard.trailingAnchor.constraint(equalTo: trailingAnchor),
            appsUsedCard.bottomAnchor.constraint(equalTo: bottomAnchor),
            appsUsedCard.widthAnchor.constraint(equalTo: longestSessionCard.widthAnchor),
            appsUsedCard.heightAnchor.constraint(equalTo: longestSessionCard.heightAnchor),
        ])
    }

    struct Data {
        let totalTime: String
        let activeTime: String
        let longestSession: String
        let appsUsed: String
    }

    func configure(with data: Data) {
        totalTimeCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Total Time",
            value: data.totalTime,
            gradient: .Preset.lavenderToSky
        ))

        activeTimeCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Active Time",
            value: data.activeTime,
            gradient: .Preset.skyToMint
        ))

        longestSessionCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Longest Session",
            value: data.longestSession,
            gradient: .Preset.peachToRose
        ))

        appsUsedCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Apps Used",
            value: data.appsUsed,
            gradient: .Preset.lavenderToLilac
        ))
    }
}
