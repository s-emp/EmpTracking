import AppKit

public extension NSColor.Base {
    static let sky50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x192535) : NSColor(hex: 0xEDF6FF) }
    static let sky100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x22334C) : NSColor(hex: 0xDAEDFF) }
    static let sky200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x2E4A6E) : NSColor(hex: 0xB5DCFF) }
    static let sky300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x58A8DB) : NSColor(hex: 0x70BCF5) }
    static let sky500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x4EB0F5) : NSColor(hex: 0x3698F0) }
}
