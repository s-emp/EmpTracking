import Foundation

public enum ControlState {
    case normal
    case hover
    case highlighted
    case disabled
}

public struct ControlParameter<T> {
    public let normal: T
    public let hover: T
    public let highlighted: T
    public let disabled: T

    public init(
        normal: T,
        hover: T? = nil,
        highlighted: T? = nil,
        disabled: T? = nil
    ) {
        self.normal = normal
        self.hover = hover ?? normal
        self.highlighted = highlighted ?? normal
        self.disabled = disabled ?? normal
    }

    public subscript(state: ControlState) -> T {
        switch state {
        case .normal:
            return normal
        case .hover:
            return hover
        case .highlighted:
            return highlighted
        case .disabled:
            return disabled
        }
    }
}

extension ControlParameter: Equatable where T: Equatable { }
