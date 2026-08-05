import SwiftUI

/// A row of equal-weight control buttons that survives Dynamic Type (§15).
///
/// **The bug this replaces.** The dense button rows — cricket's 0–6, baseball's pitch outcomes,
/// football's scoring plays — were `HStack`s of buttons with a fixed `minHeight`. At the
/// accessibility text sizes the label grew and the frame did not, so the digits were sliced in half:
/// a `0` rendered as two disconnected arcs. Unreadable, and on the hot path of every board.
///
/// Two things fix it, and both have to be here rather than at each call site:
///
/// - the minimum height is `@ScaledMetric`, so the target grows with the text rather than cropping it
/// - past `.accessibility1` the row **wraps** into fewer columns, because six buttons across a phone
///   at that size cannot hold a legible label however tall they are
struct ControlButtonGrid<Item: Hashable, Label: View>: View {
    var items: [Item]
    /// Columns at the default text sizes. Halved (minimum two) once text is at accessibility sizes.
    var columns: Int
    var label: (Item) -> Label
    var action: (Item) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 44

    private var effectiveColumns: Int {
        guard typeSize.isAccessibilitySize else { return max(1, columns) }
        return max(2, columns / 2)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: effectiveColumns),
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                Button {
                    action(item)
                } label: {
                    label(item)
                        // 44pt is Apple's minimum target, and the scaled metric only ever grows it.
                        .frame(maxWidth: .infinity, minHeight: minimumHeight)
                }
            }
        }
    }
}
