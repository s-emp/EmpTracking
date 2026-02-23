import AppKit

extension NSView {
    func apply(common viewModel: CommonViewModel) {
        wantsLayer = true
        guard let layer = layer else { return }

        // Background
        layer.backgroundColor = viewModel.backgroundColor.cgColor

        // Corners
        layer.cornerRadius = viewModel.corners.radius
        layer.maskedCorners = viewModel.corners.maskedCorners

        // Border
        switch viewModel.border.style {
        case .solid:
            removeDashedBorder()
            layer.borderWidth = viewModel.border.width
            layer.borderColor = viewModel.border.color.cgColor
        case .dashed:
            layer.borderWidth = 0
            applyDashedBorder(
                width: viewModel.border.width,
                color: viewModel.border.color,
                cornerRadius: viewModel.corners.radius
            )
        }

        // Shadow
        shadow = NSShadow()
        layer.shadowColor = viewModel.shadow.color.cgColor
        layer.shadowOffset = viewModel.shadow.offset
        layer.shadowRadius = viewModel.shadow.radius
        layer.shadowOpacity = viewModel.shadow.opacity

        // Layout Margins
        empLayoutMargins = viewModel.layoutMargins
    }

    // MARK: - Layout Margins Guide

    private static var layoutMarginsGuideKey: UInt8 = 0
    private static var layoutMarginsTopKey: UInt8 = 0
    private static var layoutMarginsLeadingKey: UInt8 = 0
    private static var layoutMarginsBottomKey: UInt8 = 0
    private static var layoutMarginsTrailingKey: UInt8 = 0
    private static var layoutMarginsInsetsKey: UInt8 = 0

    var empLayoutMarginsGuide: NSLayoutGuide {
        if let existing = objc_getAssociatedObject(self, &NSView.layoutMarginsGuideKey) as? NSLayoutGuide {
            return existing
        }

        let guide = NSLayoutGuide()
        addLayoutGuide(guide)

        let top = guide.topAnchor.constraint(equalTo: topAnchor)
        let leading = guide.leadingAnchor.constraint(equalTo: leadingAnchor)
        let bottom = bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        let trailing = trailingAnchor.constraint(equalTo: guide.trailingAnchor)

        NSLayoutConstraint.activate([top, leading, bottom, trailing])

        objc_setAssociatedObject(self, &NSView.layoutMarginsGuideKey, guide, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &NSView.layoutMarginsTopKey, top, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &NSView.layoutMarginsLeadingKey, leading, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &NSView.layoutMarginsBottomKey, bottom, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &NSView.layoutMarginsTrailingKey, trailing, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return guide
    }

    var empLayoutMargins: NSEdgeInsets {
        get {
            (objc_getAssociatedObject(self, &NSView.layoutMarginsInsetsKey) as? NSValue)?.edgeInsetsValue ?? NSEdgeInsets()
        }
        set {
            objc_setAssociatedObject(
                self,
                &NSView.layoutMarginsInsetsKey,
                NSValue(edgeInsets: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            // Trigger guide creation if needed
            _ = empLayoutMarginsGuide

            if let top = objc_getAssociatedObject(self, &NSView.layoutMarginsTopKey) as? NSLayoutConstraint {
                top.constant = newValue.top
            }
            if let leading = objc_getAssociatedObject(self, &NSView.layoutMarginsLeadingKey) as? NSLayoutConstraint {
                leading.constant = newValue.left
            }
            if let bottom = objc_getAssociatedObject(self, &NSView.layoutMarginsBottomKey) as? NSLayoutConstraint {
                bottom.constant = newValue.bottom
            }
            if let trailing = objc_getAssociatedObject(self, &NSView.layoutMarginsTrailingKey) as? NSLayoutConstraint {
                trailing.constant = newValue.right
            }
        }
    }

    // MARK: - Dashed Border Helpers

    private static var dashedBorderLayerKey: UInt8 = 0

    private var dashedBorderLayer: CAShapeLayer? {
        get { objc_getAssociatedObject(self, &NSView.dashedBorderLayerKey) as? CAShapeLayer }
        set { objc_setAssociatedObject(self, &NSView.dashedBorderLayerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private func applyDashedBorder(width: CGFloat, color: NSColor, cornerRadius: CGFloat) {
        removeDashedBorder()
        wantsLayer = true

        let shapeLayer = CAShapeLayer()
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.fillColor = nil
        shapeLayer.lineWidth = width
        shapeLayer.lineDashPattern = [6, 4]
        shapeLayer.path = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        shapeLayer.frame = bounds

        layer?.addSublayer(shapeLayer)
        dashedBorderLayer = shapeLayer
    }

    private func removeDashedBorder() {
        dashedBorderLayer?.removeFromSuperlayer()
        dashedBorderLayer = nil
    }
}
