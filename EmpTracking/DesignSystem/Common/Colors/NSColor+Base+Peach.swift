import AppKit

public extension NSColor.Base {
    static let peach50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x2E2519) : NSColor(hex: 0xFFF7EC) }
    static let peach100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x3E3223) : NSColor(hex: 0xFFECD3) }
    static let peach200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x5C482F) : NSColor(hex: 0xFFDBB4) }
    static let peach300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xD49560) : NSColor(hex: 0xF5B078) }
    static let peach500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xF5A05A) : NSColor(hex: 0xF08C42) }
}
