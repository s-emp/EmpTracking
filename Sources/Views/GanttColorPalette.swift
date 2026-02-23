import SwiftUI

enum GanttColorPalette {
    static let colors: [Color] = [
        Color(red: 0.35, green: 0.56, blue: 0.87),  // Soft blue
        Color(red: 0.27, green: 0.71, blue: 0.56),  // Teal green
        Color(red: 0.90, green: 0.55, blue: 0.34),  // Warm orange
        Color(red: 0.68, green: 0.40, blue: 0.78),  // Soft purple
        Color(red: 0.87, green: 0.43, blue: 0.50),  // Rose
        Color(red: 0.36, green: 0.67, blue: 0.73),  // Cyan
        Color(red: 0.80, green: 0.65, blue: 0.30),  // Goldenrod
        Color(red: 0.55, green: 0.75, blue: 0.40),  // Lime green
        Color(red: 0.78, green: 0.45, blue: 0.65),  // Mauve
        Color(red: 0.45, green: 0.55, blue: 0.70),  // Steel blue
        Color(red: 0.65, green: 0.55, blue: 0.40),  // Tan
        Color(red: 0.50, green: 0.70, blue: 0.60),  // Sage
        Color(red: 0.85, green: 0.50, blue: 0.60),  // Pink
        Color(red: 0.40, green: 0.60, blue: 0.50),  // Forest
        Color(red: 0.75, green: 0.60, blue: 0.50),  // Peach
        Color(red: 0.50, green: 0.50, blue: 0.75),  // Periwinkle
        Color(red: 0.70, green: 0.70, blue: 0.40),  // Olive
        Color(red: 0.60, green: 0.45, blue: 0.55),  // Plum
        Color(red: 0.45, green: 0.65, blue: 0.80),  // Sky blue
        Color(red: 0.75, green: 0.50, blue: 0.35),  // Copper
    ]

    static func colorIndex(for appName: String) -> Int {
        var hash: UInt32 = 5381
        for byte in appName.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt32(byte)
        }
        return Int(hash) % colors.count
    }

    static func color(for appName: String) -> Color {
        colors[colorIndex(for: appName)]
    }
}
