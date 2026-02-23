import AppKit

public extension NSColor.Base {
    static let lavender50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x1E1F32) : NSColor(hex: 0xF0F1FF) }
    static let lavender100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x2A2C48) : NSColor(hex: 0xE2E3FF) }
    static let lavender200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x3F4170) : NSColor(hex: 0xC9C8FD) }
    static let lavender300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x7D79DB) : NSColor(hex: 0x9B97F5) }
    static let lavender500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x8B84FF) : NSColor(hex: 0x6C63FF) }
}
