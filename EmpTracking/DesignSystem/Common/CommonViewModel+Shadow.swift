import AppKit

public extension CommonViewModel {
    struct Shadow: Equatable {
        public let color: NSColor
        public let offset: CGSize
        public let radius: CGFloat
        public let opacity: Float

        public init(
            color: NSColor = .clear,
            offset: CGSize = .zero,
            radius: CGFloat = 0,
            opacity: Float = 0
        ) {
            self.color = color
            self.offset = offset
            self.radius = radius
            self.opacity = opacity
        }
    }
}
