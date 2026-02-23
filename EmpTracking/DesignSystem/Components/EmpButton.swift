import AppKit

public final class EmpButton: NSView {
    // MARK: - Action

    public var action: (() -> Void)?

    // MARK: - State

    public var isEnabled: Bool = true {
        didSet {
            updateAppearance()
            window?.invalidateCursorRects(for: self)
        }
    }

    private var isHovered = false
    private var isPressed = false
    private var currentViewModel: ViewModel?

    // MARK: - UI Elements

    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Constraints

    private var heightConstraint: NSLayoutConstraint?

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

        addSubview(contentStack)

        let guide = empLayoutMarginsGuide
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor),
        ])

        heightConstraint = heightAnchor.constraint(equalToConstant: 32)
        heightConstraint?.isActive = true

        setupTracking()
    }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
    }

    // MARK: - Configure

    public func configure(with viewModel: ViewModel) {
        currentViewModel = viewModel

        heightConstraint?.constant = viewModel.height
        contentStack.spacing = viewModel.spacing

        layer?.masksToBounds = true

        rebuildContent(viewModel.content.normal)
        updateAppearance()
        invalidateIntrinsicContentSize()
    }

    // MARK: - Intrinsic Content Size

    override public var intrinsicContentSize: NSSize {
        let stackSize = contentStack.fittingSize
        guard let viewModel = currentViewModel else {
            return NSSize(width: stackSize.width, height: 32)
        }
        let margins = viewModel.common.normal.layoutMargins
        let hPadding = margins.left + margins.right
        return NSSize(width: stackSize.width + hPadding, height: viewModel.height)
    }

    // MARK: - Content

    private func rebuildContent(_ content: Content) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if let leading = content.leading {
            contentStack.addArrangedSubview(makeElementView(leading))
        }
        if let center = content.center {
            contentStack.addArrangedSubview(makeElementView(center))
        }
        if let trailing = content.trailing {
            contentStack.addArrangedSubview(makeElementView(trailing))
        }
    }

    private func makeElementView(_ element: Content.Element) -> NSView {
        switch element {
        case let .text(viewModel):
            let empText = EmpText()
            empText.configure(with: viewModel)
            empText.setContentCompressionResistancePriority(
                NSLayoutConstraint.Priority(rawValue: 999),
                for: .horizontal
            )
            return empText

        case let .icon(viewModel):
            let empImage = EmpImage()
            empImage.configure(with: viewModel)
            return empImage

        case let .titleSubtitle(titleVM, subtitleVM):
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2

            let titleText = EmpText()
            titleText.configure(with: titleVM)

            let subtitleText = EmpText()
            subtitleText.configure(with: subtitleVM)

            stack.addArrangedSubview(titleText)
            stack.addArrangedSubview(subtitleText)
            return stack
        }
    }

    private func updateContent(_ content: Content) {
        let elements: [Content.Element] = [content.leading, content.center, content.trailing].compactMap { $0 }

        guard contentStack.arrangedSubviews.count == elements.count else {
            rebuildContent(content)
            return
        }

        for (view, element) in zip(contentStack.arrangedSubviews, elements) {
            switch element {
            case let .text(viewModel):
                (view as? EmpText)?.configure(with: viewModel)

            case let .icon(viewModel):
                (view as? EmpImage)?.configure(with: viewModel)

            case let .titleSubtitle(titleVM, subtitleVM):
                if let stack = view as? NSStackView {
                    (stack.arrangedSubviews.first as? EmpText)?.configure(with: titleVM)
                    if stack.arrangedSubviews.count > 1, let subtitle = stack.arrangedSubviews[1] as? EmpText {
                        subtitle.configure(with: subtitleVM)
                    }
                }
            }
        }
    }

    // MARK: - State

    private var currentState: ControlState {
        if !isEnabled { return .disabled }
        if isPressed { return .highlighted }
        if isHovered { return .hover }
        return .normal
    }

    // MARK: - Appearance

    private func updateAppearance() {
        guard let viewModel = currentViewModel else { return }

        let state = currentState
        apply(common: viewModel.common[state])
        updateContent(viewModel.content[state])

        if !isEnabled {
            alphaValue = 0.4
        } else if isPressed {
            alphaValue = 0.7
        } else {
            alphaValue = 1.0
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    // MARK: - Cursor

    override public func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    // MARK: - Mouse Events

    override public func mouseEntered(with _: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        updateAppearance()
    }

    override public func mouseExited(with _: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override public func mouseDown(with _: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        updateAppearance()
    }

    override public func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        updateAppearance()

        guard isEnabled, wasPressed else { return }
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            action?()
        }
    }
}
