import AppKit

public extension NSEdgeInsets {
    init(top: EmpSpacing, left: EmpSpacing, bottom: EmpSpacing, right: EmpSpacing) {
        self.init(top: top.rawValue, left: left.rawValue, bottom: bottom.rawValue, right: right.rawValue)
    }
}
