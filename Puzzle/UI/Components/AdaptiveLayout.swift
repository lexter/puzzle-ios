import CoreGraphics

enum LayoutMode { case compact, sidePanel }

private let sidePanelMinWidth: CGFloat = 600

/// Phone portrait → compact. Wide landscape windows (iPad, iPad split view wide enough) →
/// side panel, where the board sits on the leading side.
func layoutMode(width: CGFloat, height: CGFloat) -> LayoutMode {
    width >= sidePanelMinWidth && width > height ? .sidePanel : .compact
}
