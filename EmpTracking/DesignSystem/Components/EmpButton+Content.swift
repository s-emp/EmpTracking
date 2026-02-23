import AppKit

public extension EmpButton {
    struct Content {
        public let leading: Element?
        public let center: Element?
        public let trailing: Element?

        public init(
            leading: Element? = nil,
            center: Element? = nil,
            trailing: Element? = nil
        ) {
            self.leading = leading
            self.center = center
            self.trailing = trailing
        }

        public enum Element {
            case text(EmpText.ViewModel)
            case icon(EmpImage.ViewModel)
            case titleSubtitle(title: EmpText.ViewModel, subtitle: EmpText.ViewModel)
        }
    }
}
