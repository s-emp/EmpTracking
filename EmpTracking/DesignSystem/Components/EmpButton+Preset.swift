import AppKit

// MARK: - EmpButton.Preset

public extension EmpButton {
    enum Preset {
        // MARK: Public

        public enum ColorVariant {
            case primary
            case danger
        }

        public enum Size {
            case small
            case medium
            case large
        }

        public struct ContentLayout {
            public let leading: ElementLayout?
            public let center: ElementLayout?
            public let trailing: ElementLayout?

            public init(
                leading: ElementLayout? = nil,
                center: ElementLayout? = nil,
                trailing: ElementLayout? = nil
            ) {
                self.leading = leading
                self.center = center
                self.trailing = trailing
            }

            // swiftlint:disable:next nesting
            public enum ElementLayout {
                case icon(NSImage)
                case text(String)
                case titleSubtitle(title: String, subtitle: String)
            }
        }

        // MARK: - Filled

        public static func filled(
            _ colorVariant: ColorVariant,
            content: ContentLayout,
            size: Size = .medium
        ) -> ViewModel {
            let config = SizeConfig(for: size)
            let corners = CommonViewModel.Corners(radius: config.cornerRadius)
            let margins = config.margins

            let action = actionColor(for: colorVariant)
            let hover = hoverColor(for: colorVariant)

            let styledContent = styledContent(
                from: content,
                primaryColor: NSColor.Semantic.textPrimaryInverted,
                secondaryColor: NSColor.Semantic.textSecondaryInverted,
                config: config
            )

            return ViewModel(
                common: ControlParameter(
                    normal: CommonViewModel(corners: corners, backgroundColor: action, layoutMargins: margins),
                    hover: CommonViewModel(corners: corners, backgroundColor: hover, layoutMargins: margins)
                ),
                content: ControlParameter(normal: styledContent),
                height: config.height,
                spacing: config.spacing
            )
        }

        // MARK: - Base

        public static func base(
            _ colorVariant: ColorVariant,
            content: ContentLayout,
            size: Size = .medium
        ) -> ViewModel {
            let config = SizeConfig(for: size)
            let corners = CommonViewModel.Corners(radius: config.cornerRadius)
            let margins = config.margins

            let bg = baseColor(for: colorVariant)
            let hoverBg = baseHoverColor(for: colorVariant)
            let colors = contentColors(for: colorVariant)

            let styledContent = styledContent(
                from: content,
                primaryColor: colors.primary,
                secondaryColor: colors.secondary,
                config: config
            )

            return ViewModel(
                common: ControlParameter(
                    normal: CommonViewModel(corners: corners, backgroundColor: bg, layoutMargins: margins),
                    hover: CommonViewModel(corners: corners, backgroundColor: hoverBg, layoutMargins: margins)
                ),
                content: ControlParameter(normal: styledContent),
                height: config.height,
                spacing: config.spacing
            )
        }

        // MARK: - Outlined

        public static func outlined(
            _ colorVariant: ColorVariant,
            content: ContentLayout,
            size: Size = .medium
        ) -> ViewModel {
            let config = SizeConfig(for: size)
            let corners = CommonViewModel.Corners(radius: config.cornerRadius)
            let margins = config.margins

            let action = actionColor(for: colorVariant)
            let tint = tintColor(for: colorVariant)
            let border = CommonViewModel.Border(width: 1, color: action, style: .solid)

            let styledContent = styledContent(
                from: content,
                primaryColor: action,
                secondaryColor: action,
                config: config
            )

            return ViewModel(
                common: ControlParameter(
                    normal: CommonViewModel(border: border, corners: corners, layoutMargins: margins),
                    hover: CommonViewModel(border: border, corners: corners, backgroundColor: tint, layoutMargins: margins)
                ),
                content: ControlParameter(normal: styledContent),
                height: config.height,
                spacing: config.spacing
            )
        }

        // MARK: - Ghost

        public static func ghost(
            _ colorVariant: ColorVariant,
            content: ContentLayout,
            size: Size = .medium
        ) -> ViewModel {
            let config = SizeConfig(for: size)
            let corners = CommonViewModel.Corners(radius: config.cornerRadius)
            let margins = config.margins

            let tint = tintColor(for: colorVariant)
            let colors = contentColors(for: colorVariant)

            let styledContent = styledContent(
                from: content,
                primaryColor: colors.primary,
                secondaryColor: colors.secondary,
                config: config
            )

            return ViewModel(
                common: ControlParameter(
                    normal: CommonViewModel(corners: corners, layoutMargins: margins),
                    hover: CommonViewModel(corners: corners, backgroundColor: tint, layoutMargins: margins)
                ),
                content: ControlParameter(normal: styledContent),
                height: config.height,
                spacing: config.spacing
            )
        }

        // MARK: Private

        // MARK: - Content Builder

        private static func styledContent(
            from layout: ContentLayout,
            primaryColor: NSColor,
            secondaryColor: NSColor,
            config: SizeConfig
        ) -> Content {
            func style(_ element: ContentLayout.ElementLayout) -> Content.Element {
                styledElement(element, primaryColor: primaryColor, secondaryColor: secondaryColor, config: config)
            }
            return Content(
                leading: layout.leading.map { style($0) },
                center: layout.center.map { style($0) },
                trailing: layout.trailing.map { style($0) }
            )
        }

        private static func styledElement(
            _ element: ContentLayout.ElementLayout,
            primaryColor: NSColor,
            secondaryColor: NSColor,
            config: SizeConfig
        ) -> Content.Element {
            switch element {
            case let .icon(image):
                return .icon(EmpImage.ViewModel(
                    image: image,
                    tintColor: primaryColor,
                    size: CGSize(width: config.iconSize, height: config.iconSize),
                    contentMode: .aspectFit
                ))
            case let .text(string):
                return .text(EmpText.ViewModel(
                    content: .plain(.init(
                        text: string,
                        font: config.font,
                        color: primaryColor
                    )),
                    numberOfLines: 1
                ))
            case let .titleSubtitle(title, subtitle):
                return .titleSubtitle(
                    title: EmpText.ViewModel(
                        content: .plain(.init(
                            text: title,
                            font: config.font,
                            color: primaryColor
                        )),
                        numberOfLines: 1,
                        alignment: .natural
                    ),
                    subtitle: EmpText.ViewModel(
                        content: .plain(.init(
                            text: subtitle,
                            font: config.secondaryFont,
                            color: secondaryColor
                        )),
                        numberOfLines: 1,
                        alignment: .natural
                    )
                )
            }
        }

        // MARK: - Color Helpers

        private static func actionColor(for variant: ColorVariant) -> NSColor {
            switch variant {
            case .primary:
                return NSColor.Semantic.actionPrimary
            case .danger:
                return NSColor.Semantic.actionDanger
            }
        }

        private static func hoverColor(for variant: ColorVariant) -> NSColor {
            switch variant {
            case .primary:
                return NSColor.Semantic.actionPrimaryHover
            case .danger:
                return NSColor.Semantic.actionDangerHover
            }
        }

        private static func tintColor(for variant: ColorVariant) -> NSColor {
            switch variant {
            case .primary:
                return NSColor.Semantic.actionPrimaryTint
            case .danger:
                return NSColor.Semantic.actionDangerTint
            }
        }

        private static func baseColor(for variant: ColorVariant) -> NSColor {
            switch variant {
            case .primary:
                return NSColor.Semantic.actionPrimaryBase
            case .danger:
                return NSColor.Semantic.actionDangerBase
            }
        }

        private static func baseHoverColor(for variant: ColorVariant) -> NSColor {
            switch variant {
            case .primary:
                return NSColor.Semantic.actionPrimaryBaseHover
            case .danger:
                return NSColor.Semantic.actionDangerBaseHover
            }
        }

        private static func contentColors(for variant: ColorVariant) -> (primary: NSColor, secondary: NSColor) {
            switch variant {
            case .primary:
                return (NSColor.Semantic.textPrimary, NSColor.Semantic.textSecondary)
            case .danger:
                return (NSColor.Semantic.actionDanger, NSColor.Semantic.actionDanger)
            }
        }
    }
}

// MARK: - SizeConfig

private struct SizeConfig {
    let height: CGFloat
    let font: NSFont
    let secondaryFont: NSFont
    let iconSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat

    var margins: NSEdgeInsets {
        NSEdgeInsets(
            top: verticalPadding,
            left: horizontalPadding,
            bottom: verticalPadding,
            right: horizontalPadding
        )
    }

    init(for size: EmpButton.Preset.Size) {
        switch size {
        case .small:
            height = 24
            font = .systemFont(ofSize: 11, weight: .semibold)
            secondaryFont = .systemFont(ofSize: 9)
            iconSize = 12
            horizontalPadding = EmpSpacing.xs.rawValue
            verticalPadding = EmpSpacing.xxs.rawValue
            cornerRadius = 4
            spacing = EmpSpacing.xxs.rawValue
        case .medium:
            height = 32
            font = .systemFont(ofSize: 13, weight: .semibold)
            secondaryFont = .systemFont(ofSize: 11)
            iconSize = 14
            horizontalPadding = EmpSpacing.s.rawValue
            verticalPadding = EmpSpacing.xs.rawValue
            cornerRadius = 6
            spacing = EmpSpacing.xs.rawValue
        case .large:
            height = 40
            font = .systemFont(ofSize: 14, weight: .semibold)
            secondaryFont = .systemFont(ofSize: 12)
            iconSize = 16
            horizontalPadding = EmpSpacing.m.rawValue
            verticalPadding = EmpSpacing.s.rawValue
            cornerRadius = 8
            spacing = EmpSpacing.xs.rawValue
        }
    }
}
