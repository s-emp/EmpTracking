import AppKit

public extension NSColor.Base {
    static let lemon50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x2E2A17) : NSColor(hex: 0xFFFCEB) }
    static let lemon100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x3E3820) : NSColor(hex: 0xFFF5CC) }
    static let lemon200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x5C4F2C) : NSColor(hex: 0xFFEBA5) }
    static let lemon300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xD4B648) : NSColor(hex: 0xF5D160) }
    static let lemon500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xF0C838) : NSColor(hex: 0xE8B420) }
}
