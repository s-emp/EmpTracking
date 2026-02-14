import Cocoa

final class HourBarView: NSView {
    var segments: [(color: NSColor, fraction: CGFloat)] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds
        var y = rect.minY

        for segment in segments {
            let segmentHeight = rect.height * segment.fraction
            if segmentHeight < 0.5 { continue }
            let segmentRect = NSRect(x: rect.minX, y: y, width: rect.width, height: segmentHeight)
            segment.color.setFill()
            NSBezierPath(roundedRect: segmentRect, xRadius: 0, yRadius: 0).fill()
            y += segmentHeight
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
