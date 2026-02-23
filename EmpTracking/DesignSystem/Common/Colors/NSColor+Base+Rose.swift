import AppKit

public extension NSColor.Base {
    static let rose50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x2E191E) : NSColor(hex: 0xFFF0F1) }
    static let rose100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x3E2328) : NSColor(hex: 0xFFDEE2) }
    static let rose200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x5C303B) : NSColor(hex: 0xFFC8CF) }
    static let rose300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xD86E7C) : NSColor(hex: 0xF58C99) }
    static let rose500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xF07080) : NSColor(hex: 0xE85468) }
}
