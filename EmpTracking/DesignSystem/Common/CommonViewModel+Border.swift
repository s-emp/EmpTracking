import AppKit

public extension CommonViewModel {
    struct Border: Equatable {
        public let width: CGFloat
        public let color: NSColor
        public let style: Style

        public enum Style {
            case solid
            case dashed
        }

        public init(
            width: CGFloat = 0,
            color: NSColor = .clear,
            style: Style = .solid
        ) {
            self.width = width
            self.color = color
            self.style = style
        }
    }
}
