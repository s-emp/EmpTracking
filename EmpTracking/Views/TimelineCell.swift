import Cocoa

final class TimelineCell: NSCollectionViewItem {
    let barView = HourBarView()
    let labelButton = NSButton()

    private var trackingArea: NSTrackingArea?

    var onTap: (() -> Void)?
    var isHighlighted: Bool = false {
        didSet {
            barView.layer?.borderWidth = isHighlighted ? 2 : 0
            barView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    override func loadView() {
        let container = NSView()
        self.view = container

        barView.translatesAutoresizingMaskIntoConstraints = false
        barView.wantsLayer = true
        barView.layer?.cornerRadius = 3
        container.addSubview(barView)

        labelButton.translatesAutoresizingMaskIntoConstraints = false
        labelButton.isBordered = false
        labelButton.font = .systemFont(ofSize: 10)
        labelButton.target = self
        labelButton.action = #selector(labelTapped)
        container.addSubview(labelButton)

        NSLayoutConstraint.activate([
            barView.topAnchor.constraint(equalTo: container.topAnchor),
            barView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 1),
            barView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -1),
            barView.bottomAnchor.constraint(equalTo: labelButton.topAnchor, constant: -4),

            labelButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            labelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            labelButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTrackingArea()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            view.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        labelButton.font = .systemFont(ofSize: 10, weight: .bold)
    }

    override func mouseExited(with event: NSEvent) {
        labelButton.font = .systemFont(ofSize: 10, weight: .regular)
    }

    @objc private func labelTapped() {
        onTap?()
    }

    func configure(label: String, segments: [(color: NSColor, fraction: CGFloat)]) {
        labelButton.title = label
        barView.segments = segments
    }
}
