// The results card for the last Send (No Figma: derived, styled after the comment card): a glass
// card listing every sent pin with what the agent reported for it (resolved, dismissed, a question,
// answered, or still waiting). A header names the Send and summarizes the outcomes, × closes the
// card, and a question row carries a Reply button that opens the reply card for that pin. Outcome
// copy, tone and glyph come from `PinOutcome` in AnnotateCore, so the view never decides them.
// OverlayRoot places it above `chromeBottom` like the comment card.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct ResultsCard: View {
    let controller: AnnotateController

    /// Measured height of the rows, so the list hugs short content and scrolls past the cap.
    @State private var rowsHeight: CGFloat = 0

    /// Card corner radius, the comment card's 32 (ComposerCard).
    static let cornerRadius: CGFloat = 32
    /// Contract: the row list stops growing at 320pt and scrolls beyond it.
    static let maxListHeight: CGFloat = 320
    /// Contract: header px 20, pt 16, pb 8; rows px 20, py 10.
    static let horizontalPadding: CGFloat = 20
    static let headerTopPadding: CGFloat = 16
    static let headerBottomPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 10
    /// Contract: badge to text gap 12, title to subtitle gap 2.
    static let rowSpacing: CGFloat = 12
    static let textSpacing: CGFloat = 2
    /// Contract: Reply capsule height 32, px 12.
    static let replyHeight: CGFloat = 32
    static let replyHorizontalPadding: CGFloat = 12

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    var body: some View {
        let results = controller.pinResults

        VStack(alignment: .leading, spacing: 0) {
            header(results)
            rows(results)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .annotateGlass(in: shape, interactive: true)
        // Glass alone isn't hit-testable: a tap between rows must not reach the frozen screen
        .contentShape(shape)
        .onTapGesture {}
    }

    // MARK: - Header

    private func header(_ results: [PinResult]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Self.textSpacing) {
                Text(OverlayChrome.resultsTitle(results.count))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                if let summary = PinResult.summary(results) {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            CircleIconButton(systemName: "xmark") { controller.closeResults() }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, Self.headerTopPadding)
        .padding(.bottom, Self.headerBottomPadding)
    }

    // MARK: - Rows

    private func rows(_ results: [PinResult]) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { result in
                    row(result)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
        }
        // Hugs the rows until they pass the cap, then scrolls
        .frame(height: min(rowsHeight, Self.maxListHeight))
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    private func row(_ result: PinResult) -> some View {
        let outcome = result.outcome
        return HStack(alignment: .top, spacing: Self.rowSpacing) {
            // Badge and text read as one element; the Reply button stays its own
            HStack(alignment: .top, spacing: Self.rowSpacing) {
                ResultBadge(number: result.index, outcome: outcome)
                VStack(alignment: .leading, spacing: Self.textSpacing) {
                    Text(outcome.label + (outcome.detail.map { " · \($0)" } ?? ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Text(result.comment.isEmpty ? result.subject : result.comment)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            if outcome.isQuestion {
                Button {
                    controller.beginReply(pin: result.index)
                } label: {
                    Text(OverlayChrome.replyAction)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Self.replyHorizontalPadding)
                        .frame(height: Self.replyHeight)
                        .background(AnnotateStyle.action, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityLabel("\(OverlayChrome.replyAction) to note \(result.index)")
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
    }
}

/// The 24pt outcome badge: tone sets the fill, and it shows the outcome's glyph when it has one,
/// otherwise the pin number (contract K4).
private struct ResultBadge: View {
    let number: Int
    let outcome: PinOutcome

    var body: some View {
        Group {
            if let symbol = outcome.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
            }
        }
        .frame(width: AnnotateStyle.badgeSize, height: AnnotateStyle.badgeSize)
        .background(Circle().fill(fill))
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch outcome.tone {
        case .neutral: AnnotateStyle.marker
        case .success: Color(uiColor: .systemGreen)
        case .muted: Color(uiColor: .systemGray)
        case .attention: Color(uiColor: .systemOrange)
        }
    }

    /// Black on the white neutral badge (like `PinBadge`), white on the colored ones.
    private var numberColor: Color {
        switch outcome.tone {
        case .neutral: AnnotateStyle.badgeText
        case .success, .muted, .attention: .white
        }
    }
}
#endif
