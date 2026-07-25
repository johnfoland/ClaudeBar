import AppKit
import SwiftUI
import Domain

/// Fork-only menu bar text color.
///
/// Upstream tints the menu-bar usage readout by quota status (green healthy,
/// orange warning, red critical/depleted). This fork always draws it in the
/// menu bar's default text color, so the numbers read as ordinary menu bar
/// text. Status is still conveyed everywhere else: the dropdown, the icon-only
/// fallback, and the notifications.
///
/// Lives in its own file and is consumed from the text call sites in
/// `StatusItemLabelDriver.compose(_:theme:)`, keeping the fork's footprint in
/// that upstream file down to the lines that pick a color.
extension AppThemeProvider {
    /// Color for the menu-bar usage text, in place of upstream's status tint.
    ///
    /// Defaults to the menu bar's own text color for every theme; a theme that
    /// wants its own menu-bar color can override this single property.
    @MainActor
    var forkMenuBarTextColor: Color { ForkMenuBarStyle.defaultTextColor }
}

/// Fork-only menu bar styling values.
@MainActor
enum ForkMenuBarStyle {
    /// The menu bar's default text color: white on a dark menu bar, black on a
    /// light one.
    ///
    /// Resolved eagerly from the app's effective appearance — the same
    /// `bestMatch` the driver uses to resolve a theme — rather than left to a
    /// dynamic `NSColor`. The status-item image is deliberately non-template
    /// (it has to preserve the session glyph's color), so nothing resolves a
    /// dynamic color for us at draw time.
    static var defaultTextColor: Color {
        let isDark = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .white : .black
    }
}
