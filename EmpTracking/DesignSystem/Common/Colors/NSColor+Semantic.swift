import AppKit

// MARK: - NSColor.Semantic

public extension NSColor {
    enum Semantic { }
}

public extension NSColor.Semantic {
    // MARK: - Backgrounds

    static let backgroundPrimary = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x0A0A0A) : .white }
    static let backgroundSecondary = NSColor.Base.neutral50
    static let backgroundTertiary = NSColor.Base.neutral100

    // MARK: - Cards

    static let cardLavender = NSColor.Base.lavender50
    static let cardBorderLavender = NSColor.Base.lavender200
    static let cardMint = NSColor.Base.mint50
    static let cardBorderMint = NSColor.Base.mint200
    static let cardPeach = NSColor.Base.peach50
    static let cardBorderPeach = NSColor.Base.peach200
    static let cardRose = NSColor.Base.rose50
    static let cardBorderRose = NSColor.Base.rose200
    static let cardSky = NSColor.Base.sky50
    static let cardBorderSky = NSColor.Base.sky200
    static let cardLemon = NSColor.Base.lemon50
    static let cardBorderLemon = NSColor.Base.lemon200
    static let cardLilac = NSColor.Base.lilac50
    static let cardBorderLilac = NSColor.Base.lilac200

    // MARK: - Borders

    static let borderDefault = NSColor.Base.neutral200
    static let borderSubtle = NSColor.Base.neutral100

    // MARK: - Text

    static let textPrimary = NSColor.Base.neutral900
    static let textSecondary = NSColor.Base.neutral500
    static let textTertiary = NSColor.Base.neutral300
    static let textAccent = NSColor.Base.lavender500

    // MARK: - Text - Inverted (on colored backgrounds)

    static let textPrimaryInverted = NSColor.Base.neutralInverted900
    static let textSecondaryInverted = NSColor.Base.neutralInverted500

    // MARK: - Actions

    static let actionPrimary = NSColor.Base.lavender500
    static let actionSuccess = NSColor.Base.mint500
    static let actionWarning = NSColor.Base.peach500
    static let actionDanger = NSColor.Base.rose500
    static let actionInfo = NSColor.Base.sky500

    // MARK: - Actions - Hover

    static let actionPrimaryHover = NSColor.Base.lavender300
    static let actionDangerHover = NSColor.Base.rose300

    // MARK: - Actions - Tint (subtle background)

    static let actionPrimaryTint = NSColor.Base.lavender50
    static let actionDangerTint = NSColor.Base.rose50

    // MARK: - Actions - Base (subtle filled)

    static let actionPrimaryBase = NSColor.Base.neutral100
    static let actionPrimaryBaseHover = NSColor.Base.neutral200
    static let actionDangerBase = NSColor.Base.rose50
    static let actionDangerBaseHover = NSColor.Base.rose100
}
