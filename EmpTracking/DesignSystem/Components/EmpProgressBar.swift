import AppKit

public final class EmpProgressBar: NSView {
    // MARK: - ViewModel

    public struct ViewModel {
        // MARK: Public

        public let common: CommonViewModel
        public let progress: CGFloat
        public let trackColor: NSColor
        public let fillColor: NSColor
        public let barHeight: CGFloat

        public init(
            common: CommonViewModel = CommonViewModel(),
            progress: CGFloat = 0,
            trackColor: NSColor = NSColor.Semantic.backgroundTertiary,
            fillColor: NSColor = NSColor.Semantic.actionPrimary,
            barHeight: CGFloat = 4
        ) {
            self.common = common
            self.progress = min(max(progress, 0), 1)
            self.trackColor = trackColor
            self.fillColor = fillColor
            self.barHeight = barHeight
        }
    }

    // MARK: - UI Elements

    private let trackView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let fillView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Constraints

    private var trackHeightConstraint: NSLayoutConstraint?
    private var fillWidthConstraint: NSLayoutConstraint?

    // MARK: - State

    private var currentProgress: CGFloat = 0

    // MARK: - Init

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        addSubview(trackView)
        trackView.addSubview(fillView)

        let guide = empLayoutMarginsGuide
        let heightConstraint = trackView.heightAnchor.constraint(equalToConstant: 4)
        trackHeightConstraint = heightConstraint

        let widthConstraint = fillView.widthAnchor.constraint(equalToConstant: 0)
        fillWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            trackView.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            heightConstraint,

            fillView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            fillView.topAnchor.constraint(equalTo: trackView.topAnchor),
            fillView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor),
            widthConstraint,
        ])
    }

    // MARK: - Configure

    public func configure(with viewModel: ViewModel) {
        apply(common: viewModel.common)

        currentProgress = viewModel.progress

        trackView.layer?.backgroundColor = viewModel.trackColor.cgColor
        fillView.layer?.backgroundColor = viewModel.fillColor.cgColor

        let cornerRadius = viewModel.barHeight / 2
        trackView.layer?.cornerRadius = cornerRadius
        fillView.layer?.cornerRadius = cornerRadius
        trackView.layer?.masksToBounds = true

        trackHeightConstraint?.constant = viewModel.barHeight
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    // MARK: - Layout

    override public func layout() {
        super.layout()
        let trackWidth = trackView.bounds.width
        fillWidthConstraint?.constant = trackWidth * currentProgress
    }

    override public var intrinsicContentSize: NSSize {
        let margins = empLayoutMargins
        let height = (trackHeightConstraint?.constant ?? 4) + margins.top + margins.bottom
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}
