import AppKit

public extension NSColor.Base {
    static let lilac50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x26192E) : NSColor(hex: 0xF8F0FF) }
    static let lilac100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x33233E) : NSColor(hex: 0xEEDDFF) }
    static let lilac200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x48305C) : NSColor(hex: 0xDFC6FF) }
    static let lilac300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xA86ED8) : NSColor(hex: 0xBE8AF5) }
    static let lilac500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xB56EF5) : NSColor(hex: 0x9C52E0) }
}
