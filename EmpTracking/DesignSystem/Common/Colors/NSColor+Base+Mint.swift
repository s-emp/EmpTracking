import AppKit

public extension NSColor.Base {
    static let mint50 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x192E28) : NSColor(hex: 0xEDFCF8) }
    static let mint100 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x223E34) : NSColor(hex: 0xD4F5EA) }
    static let mint200 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x2E5A4C) : NSColor(hex: 0xB0ECDA) }
    static let mint300 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x52BEA4) : NSColor(hex: 0x6DD4BC) }
    static let mint500 = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x3ED4AE) : NSColor(hex: 0x2FB894) }
}
