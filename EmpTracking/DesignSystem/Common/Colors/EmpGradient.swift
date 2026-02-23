import AppKit

public struct EmpGradient: Equatable {
    public let startColor: NSColor
    public let endColor: NSColor

    public init(startColor: NSColor, endColor: NSColor) {
        self.startColor = startColor
        self.endColor = endColor
    }

    public func resolvedColors(for appearance: NSAppearance) -> (start: CGColor, end: CGColor) {
        var start = CGColor.clear
        var end = CGColor.clear
        appearance.performAsCurrentDrawingAppearance {
            start = startColor.cgColor
            end = endColor.cgColor
        }
        return (start, end)
    }
}
