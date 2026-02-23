import AppKit

public extension NSColor.Base {
    static let neutral50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x171717) : NSColor(hex: 0xFAFAFA) }
    static let neutral100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x262626) : NSColor(hex: 0xF5F5F5) }
    static let neutral200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x404040) : NSColor(hex: 0xE5E5E5) }
    static let neutral300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x525252) : NSColor(hex: 0xD4D4D4) }
    static let neutral500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xA3A3A3) : NSColor(hex: 0x737373) }
    static let neutral700 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xD4D4D4) : NSColor(hex: 0x404040) }
    static let neutral900 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xFAFAFA) : NSColor(hex: 0x171717) }

    // MARK: - Inverted (always light, for colored backgrounds)

    static let neutralInverted900 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xFAFAFA) : NSColor(hex: 0xFFFFFF) }
    static let neutralInverted500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xD4D4D4) : NSColor(hex: 0xE5E5E5) }
}
