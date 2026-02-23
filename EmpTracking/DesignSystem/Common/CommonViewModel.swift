import AppKit

public struct CommonViewModel: Equatable {
    // MARK: - Properties

    public let border: Border
    public let shadow: Shadow
    public let corners: Corners
    public let backgroundColor: NSColor
    public let layoutMargins: NSEdgeInsets

    // MARK: - Init

    public init(
        border: Border = Border(),
        shadow: Shadow = Shadow(),
        corners: Corners = Corners(),
        backgroundColor: NSColor = .clear,
        layoutMargins: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    ) {
        self.border = border
        self.shadow = shadow
        self.corners = corners
        self.backgroundColor = backgroundColor
        self.layoutMargins = layoutMargins
    }
}
