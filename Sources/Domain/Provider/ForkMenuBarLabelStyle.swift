import Foundation

/// Fork-only restyling of a composed `MenuBarLabel`.
///
/// Upstream renders a dual-window label as `"5h 83% · 25m | 7d 51% · 3d"`: each
/// window carries its `QuotaType.shortLabel` prefix, a window's percentage and
/// duration are joined with `·`, and the two windows with `|`. This fork drops
/// the prefixes and swaps the two separators, so the same label reads
/// `"83% | 25m • 51% | 3d"`.
///
/// Written as a transform applied on top of whatever
/// `QuotaMonitor.menuBarLabel(...)` returned, in its own file, so upstream
/// changes to the label composition merge without touching the fork's format.
public extension MenuBarLabel {
    /// Joins a window's percentage and duration. Upstream uses `·` here.
    static let forkWithinWindowSeparator = " | "

    /// Joins the two quota windows on the single-line label. Upstream uses `|`.
    static let forkBetweenWindowSeparator = " • "

    /// The separator `QuotaMonitor` puts between a window's percentage and its
    /// duration — the one this restyling rewrites.
    static let upstreamWithinWindowSeparator = " · "

    /// The label restyled into the fork's menu bar format: window prefixes
    /// removed, `percentage | duration` inside a window, ` • ` between windows.
    ///
    /// Every `status` (per segment and label-level) is carried through
    /// untouched, so this only changes text — status-driven decisions elsewhere
    /// keep working. Applying it twice is a no-op: a restyled label has no
    /// prefix and no upstream separator left to rewrite.
    ///
    /// - Parameters:
    ///   - primaryQuotaKey: quota key behind the first segment, used to
    ///     recognize the prefix upstream put on it.
    ///   - secondaryQuotaKey: the same, for the second segment.
    func forkStyled(primaryQuotaKey: String, secondaryQuotaKey: String) -> MenuBarLabel {
        // Upstream only prefixes segments when two windows share the label; a
        // single-window label already carries its bare text.
        let prefixes: [String] = segments.count == 2
            ? [primaryQuotaKey, secondaryQuotaKey].map { QuotaType(quotaKey: $0)?.shortLabel ?? $0 }
            : []

        let restyled = segments.enumerated().map { (index, segment) in
            Segment(
                text: Self.restyled(
                    segment.text,
                    strippingPrefix: prefixes.indices.contains(index) ? prefixes[index] : nil
                ),
                status: segment.status
            )
        }

        return MenuBarLabel(
            text: restyled.map(\.text).joined(separator: Self.forkBetweenWindowSeparator),
            status: status,
            segments: restyled
        )
    }

    private static func restyled(_ text: String, strippingPrefix prefix: String?) -> String {
        var text = text
        if let prefix, !prefix.isEmpty, text.hasPrefix("\(prefix) ") {
            text = String(text.dropFirst(prefix.count + 1))
        }
        return text.replacingOccurrences(
            of: upstreamWithinWindowSeparator,
            with: forkWithinWindowSeparator
        )
    }
}
