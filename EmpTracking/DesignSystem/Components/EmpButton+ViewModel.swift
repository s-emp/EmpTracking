import AppKit

public extension EmpButton {
    struct ViewModel {
        public let common: ControlParameter<CommonViewModel>
        public let content: ControlParameter<Content>
        public let height: CGFloat
        public let spacing: CGFloat

        public init(
            common: ControlParameter<CommonViewModel>,
            content: ControlParameter<Content>,
            height: CGFloat,
            spacing: CGFloat
        ) {
            self.common = common
            self.content = content
            self.height = height
            self.spacing = spacing
        }
    }
}
