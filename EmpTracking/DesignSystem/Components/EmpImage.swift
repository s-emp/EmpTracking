import AppKit

public final class EmpImage: NSView {
    // MARK: - ViewModel

    public struct ViewModel {
        public let common: CommonViewModel
        public let image: NSImage
        public let tintColor: NSColor?
        public let size: CGSize
        public let contentMode: ContentMode

        public enum ContentMode {
            case aspectFit
            case aspectFill
            case center
        }

        public init(
            common: CommonViewModel = CommonViewModel(),
            image: NSImage,
            tintColor: NSColor? = nil,
            size: CGSize,
            contentMode: ContentMode = .aspectFit
        ) {
            self.common = common
            self.image = image
            self.tintColor = tintColor
            self.size = size
            self.contentMode = contentMode
        }
    }

    // MARK: - UI Elements

    private let imageView: NSImageView = {
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageFrameStyle = .none
        iv.isEditable = false
        iv.imageAlignment = .alignCenter
        return iv
    }()

    // MARK: - Constraints

    private var widthConstraint: NSLayoutConstraint?
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
        addSubview(imageView)

        let guide = empLayoutMarginsGuide
        let wc = imageView.widthAnchor.constraint(equalToConstant: 0)
        let hc = imageView.heightAnchor.constraint(equalToConstant: 0)
        widthConstraint = wc
        heightConstraint = hc

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: guide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            wc,
            hc,
        ])
    }

    // MARK: - Configure

    public func configure(with viewModel: ViewModel) {
        apply(common: viewModel.common)
        layer?.masksToBounds = true

        imageView.contentTintColor = viewModel.tintColor

        switch viewModel.contentMode {
        case .aspectFit:
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.image = viewModel.image
        case .aspectFill:
            imageView.imageScaling = .scaleNone
            imageView.image = scaledImage(viewModel.image, toFill: viewModel.size)
        case .center:
            imageView.imageScaling = .scaleNone
            imageView.image = viewModel.image
        }

        widthConstraint?.constant = viewModel.size.width
        heightConstraint?.constant = viewModel.size.height
    }

    // MARK: - Aspect Fill

    private func scaledImage(_ image: NSImage, toFill targetSize: CGSize) -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let scale = max(widthRatio, heightRatio)

        let scaledSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let origin = CGPoint(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2
        )

        let result = NSImage(size: targetSize, flipped: false) { _ in
            image.draw(
                in: CGRect(origin: origin, size: scaledSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            return true
        }
        result.isTemplate = image.isTemplate
        return result
    }
}
