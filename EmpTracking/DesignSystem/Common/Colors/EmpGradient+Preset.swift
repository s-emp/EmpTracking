import AppKit

public extension EmpGradient {
    enum Preset {
        // MARK: - Soft (step 200)

        public static let lavenderToSky = EmpGradient(startColor: NSColor.Base.lavender200, endColor: NSColor.Base.sky200)
        public static let skyToMint = EmpGradient(startColor: NSColor.Base.sky200, endColor: NSColor.Base.mint200)
        public static let peachToRose = EmpGradient(startColor: NSColor.Base.peach200, endColor: NSColor.Base.rose200)
        public static let roseToLilac = EmpGradient(startColor: NSColor.Base.rose200, endColor: NSColor.Base.lilac200)

        // MARK: - Saturated (step 300)

        public static let lavenderToLilac = EmpGradient(startColor: NSColor.Base.lavender300, endColor: NSColor.Base.lilac300)
        public static let lemonToPeach = EmpGradient(startColor: NSColor.Base.lemon300, endColor: NSColor.Base.peach300)
        public static let lavenderToMint = EmpGradient(startColor: NSColor.Base.lavender300, endColor: NSColor.Base.mint300)
        public static let skyToLavender = EmpGradient(startColor: NSColor.Base.sky300, endColor: NSColor.Base.lavender300)
    }
}
