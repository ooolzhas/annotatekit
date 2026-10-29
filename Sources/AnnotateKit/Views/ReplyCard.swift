// The reply card for one sent pin the agent asked about: an orange "<Agent> asks about note N"
// header, the pin's earlier exchange (if the agent asked before), the question, the reply field, and
// the × / ↑ row. No Figma: derived from ComposerCard's
// layout (glass radius 32, 20pt text insets, 44pt circle buttons) so both keyboard-docked cards
// read as one family. It only lays itself out at the width it is given; OverlayRoot docks it to
// the keyboard and adds the 8pt inset. ↑ sends through the controller, which decides via `chrome`
// whether the reply can be submitted; Return types a newline.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct ReplyCard: View {
    let controller: AnnotateController
    let reply: AnnotateController.ReplyDraft

    @FocusState private var isFocused: Bool
    /// ↑ was tapped with the keyboard up: the card is hidden, waiting for the keyboard to slide away.
    @State private var isLeaving = false

    /// No Figma: derived. The orange matches `ReviewHint.Dot.attention`, the question's tone
    /// elsewhere in the overlay, so the card reads as the answer to that hint.
    private static let dotSize: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if !earlierLines.isEmpty {
                earlier
            }

            // No Figma: derived. Same type as the field below so the question and the answer
            // read as one exchange; capped so a long question can't push the card off screen
            Text(reply.question)
                .font(.body.leading(.loose))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, earlierLines.isEmpty ? 6 : 10)

            TextField("", text: replyBinding, axis: .vertical)
                .font(.body.leading(.loose))
                .foregroundStyle(.primary)
                // Same growth cap as the comment field, so the card doesn't climb over the screen
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                // Return types a newline; ↑ sends
                .focused($isFocused)
                .accessibilityLabel("Reply")
                // The drawn placeholder is hidden from VoiceOver; announce it as the hint instead
                .accessibilityHint(OverlayChrome.replyPlaceholder)
                .overlay(alignment: .topLeading) { placeholder }
                .padding(.horizontal, 20)
                // As ComposerCard: SwiftUI puts the loose leading below the glyphs, so shift 2pt
                // down (18 + 14 keeps a 16 + 16 field)
                .padding(.top, 18)
                .padding(.bottom, 14)

            buttonRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .annotateGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: true)
        // Glass alone isn't hit-testable: without this, a tap that misses a button falls through
        // to the frozen screen and starts a new pin. No card-wide tap gesture, as ComposerCard: it
        // can take taps meant for a menu drawn over the card.
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .modifier(SendAfterKeyboard(isLeaving: $isLeaving) { controller.submitReply() })
        .onAppear { isFocused = true }
    }

    // MARK: - Header

    /// No Figma: derived. px 20, pt 16, dot + title at gap 6, SF Pro Medium 15 secondary (the
    /// overlay's secondary text size).
    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(uiColor: .systemOrange))
                .frame(width: Self.dotSize, height: Self.dotSize)
                .accessibilityHidden(true)
            Text(OverlayChrome.askedTitle(agent: controller.agent?.agent ?? "", pin: reply.pin))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Earlier exchange

    /// "Claude: …" / "You: …" for the messages before this question, the last `threadLimit` of them.
    private var earlierLines: [String] {
        let agent = controller.agent?.agent ?? ""
        return reply.earlier.suffix(OverlayChrome.threadLimit).map { OverlayChrome.threadLine($0, agent: agent) }
    }

    /// No Figma: derived. Secondary 15pt like the header, 2 lines each, so the context stays smaller
    /// than the question it leads to.
    private var earlier: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(earlierLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    // The docked card is short on height; without this the line is squeezed to one
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Text

    /// The live reply text; `reply` is the snapshot OverlayRoot passed, the controller is current.
    private var replyText: String {
        controller.replyDraft?.text ?? reply.text
    }

    /// "Reply" at 50% opacity, drawn over the field as ComposerCard does because iOS 26 ignores
    /// `prompt:` styling and renders the system placeholder color instead.
    @ViewBuilder
    private var placeholder: some View {
        if replyText.isEmpty {
            Text(OverlayChrome.replyPlaceholder)
                .font(.body.leading(.loose))
                .foregroundStyle(.primary.opacity(0.5))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Newlines are kept: a reply can run over several lines.
    private var replyBinding: Binding<String> {
        Binding(
            get: { controller.replyDraft?.text ?? "" },
            set: { [controller] text in controller.setReplyText(text) }
        )
    }

    // MARK: - Buttons

    /// From `chrome`, never from the text, so the rule lives in OverlayChrome.resolve.
    private var canSubmit: Bool {
        if case .replying(let value) = controller.chrome {
            return value
        }
        return false
    }

    /// As ComposerCard's row: pb 8, px 8, right group gap 6. No paperclip: a reply is text only.
    private var buttonRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                CircleIconButton(systemName: "xmark") { controller.cancelReply() }
                    .accessibilityLabel("Cancel reply")
                // Only `.dimmed` dims; `.disabled` just blocks the tap (submitReply no-ops anyway
                // when it can't submit)
                CircleIconButton(systemName: "arrow.up", style: canSubmit ? .prominent : .dimmed) {
                    guard controller.isKeyboardUp else {
                        controller.submitReply()
                        return
                    }
                    // Hide now, let the keyboard slide away, then send (SendAfterKeyboard)
                    isLeaving = true
                    isFocused = false
                }
                .disabled(!canSubmit)
                .accessibilityLabel("Send reply")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}
#endif
