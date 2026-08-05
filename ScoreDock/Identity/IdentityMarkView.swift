import SwiftUI

/// Renders a resolved identity mark (§7.1a).
///
/// There is no empty state by construction — `ResolvedMark` always terminates at initials, so a
/// list row or a board slot can never come out blank.
struct IdentityMarkView: View {
    var mark: ResolvedMark
    var colorHex: String?
    var size: CGFloat
    /// Lists render circular; the board renders square. Same asset, cropped square at import so
    /// both read correctly (§7.1a).
    var isCircular: Bool = true
    /// A subtle ring so a light crest stays visible on a light theme (§7.1a).
    var showsContrastRing: Bool = true

    private var tint: Color { Color(hex: colorHex ?? "#1E88E5") }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                if showsContrastRing {
                    shape.strokeBorder(.primary.opacity(0.18), lineWidth: max(1, size * 0.02))
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch mark {
        case let .image(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    // Contain-fit, not fill: a crest cropped by the frame looks broken.
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.06)
                    .background(Color(.secondarySystemBackground))
            } else {
                fallbackInitials("?")
            }
        case let .emoji(emoji):
            Text(emoji)
                .font(.system(size: size * 0.58))
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tint.opacity(0.15))
        case let .initials(initials):
            fallbackInitials(initials)
        }
    }

    private func fallbackInitials(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.4)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint)
    }

    private var shape: AnyInsettableShape {
        isCircular
            ? AnyInsettableShape(Circle())
            : AnyInsettableShape(RoundedRectangle(cornerRadius: size * 0.18))
    }
}

extension IdentityMarkView {
    init(_ bearer: some IdentityBearing, size: CGFloat, isCircular: Bool = true) {
        self.init(
            mark: bearer.resolvedMark,
            colorHex: bearer.identityColorHex,
            size: size,
            isCircular: isCircular
        )
    }
}

/// Type-erased insettable shape, so `strokeBorder` works for both circle and rounded-rect cases.
struct AnyInsettableShape: InsettableShape {
    private let makePath: @Sendable (CGRect) -> Path
    private let makeInset: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        makePath = { shape.path(in: $0) }
        makeInset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { makePath(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { makeInset(amount) }
}

#Preview {
    HStack(spacing: 16) {
        IdentityMarkView(mark: .emoji("🐺"), colorHex: "#42A5F5", size: 64)
        IdentityMarkView(mark: .initials("DL"), colorHex: "#EF5350", size: 64)
        IdentityMarkView(mark: .initials("WOL"), colorHex: "#2E7D32", size: 64, isCircular: false)
    }
    .padding()
}
