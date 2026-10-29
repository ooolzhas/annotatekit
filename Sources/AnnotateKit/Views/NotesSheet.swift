// The note list behind the review bar's count (no Figma: owner request). A sheet that opens at a
// small detent and drags up to full height. It lists the pins waiting to be sent, numbered like their
// badges: a tap opens one on the comment card (pins on another screen can't open here, so they only
// list), a swipe deletes one, and Delete All clears them all after asking. Below them come the last
// Send's pins with what the agent reported, the same spinner / glyph / number as their badges, and
// Reply on a question. Row copy comes from `PinResult` and `PinOutcome` in AnnotateCore.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct NotesSheet: View {
    let controller: AnnotateController

    @State private var detent: PresentationDetent = Self.compactDetent
    @State private var isConfirmingClear = false

    /// The small detent the sheet opens at: the title and about three rows, so the frozen screen
    /// stays mostly visible. Dragging up gives the full-height list.
    static let compactDetent: PresentationDetent = .fraction(0.4)
    /// Badge to text gap, and title to subtitle gap (the results card's 12 / 2).
    static let rowSpacing: CGFloat = 12
    static let textSpacing: CGFloat = 2

    var body: some View {
        let pending = PinResult.results(for: controller.annotations, statuses: [])
        let sent = controller.pinResults

        NavigationStack {
            List {
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { note in
                            pendingRow(note)
                        }
                        .onDelete { offsets in
                            let ids = offsets.compactMap { annotationID(for: pending[$0].index) }
                            ids.forEach(controller.deleteNote)
                        }
                    } header: {
                        if !sent.isEmpty { Text(OverlayChrome.unsentTitle) }
                    }
                }
                if !sent.isEmpty {
                    Section {
                        ForEach(sent) { result in
                            sentRow(result)
                        }
                    } header: {
                        Text(OverlayChrome.resultsTitle(sent.count))
                    } footer: {
                        if let summary = PinResult.summary(sent) { Text(summary) }
                    }
                }
            }
            .navigationTitle(controller.reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !pending.isEmpty {
                        Button(OverlayChrome.clearAllTitle, role: .destructive) { isConfirmingClear = true }
                            .tint(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        controller.closeNotes()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .confirmationDialog(OverlayChrome.clearTitle(pending.count), isPresented: $isConfirmingClear,
                                titleVisibility: .visible) {
                Button(OverlayChrome.clearAction, role: .destructive) {
                    controller.clearAll()
                    controller.closeNotes()
                }
            }
        }
        .presentationDetents([Self.compactDetent, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Rows

    /// A pin waiting to be sent: its number, comment, and what it points at (plus its intent when it
    /// isn't a plain fix). Tapping opens it on the card, when it's on the screen showing.
    private func pendingRow(_ note: PinResult) -> some View {
        let id = annotationID(for: note.index)
        let isHere = controller.annotations.first { $0.index == note.index }?.screen == controller.currentScreen
        // A pin saved without a comment titles itself by what it points at
        let title = note.comment.isEmpty ? note.subject : note.comment
        var details = note.comment.isEmpty ? [] : [note.subject]
        if note.intent != .fix { details.append(note.intent.title) }
        if !isHere { details.append(OverlayChrome.otherScreenNote) }

        return Button {
            guard let id else { return }
            controller.closeNotes()
            controller.openExisting(id)
        } label: {
            HStack(spacing: Self.rowSpacing) {
                NoteBadge(number: note.index, mark: .number)
                VStack(alignment: .leading, spacing: Self.textSpacing) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isHere)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isHere ? "Open the note" : "")
    }

    /// A pin from the last Send: what the agent reported and the comment, with Reply on a question.
    private func sentRow(_ result: PinResult) -> some View {
        let outcome = result.outcome
        let mark = SentPinMark.resolve(outcome: outcome, delivery: controller.delivery)
        return HStack(spacing: Self.rowSpacing) {
            HStack(spacing: Self.rowSpacing) {
                NoteBadge(number: result.index, mark: mark)
                VStack(alignment: .leading, spacing: Self.textSpacing) {
                    Text(outcome.label + (outcome.detail.map { " · \($0)" } ?? ""))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Text(result.comment.isEmpty ? result.subject : result.comment)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            if outcome.isQuestion {
                Button(OverlayChrome.replyAction) {
                    controller.closeNotes()
                    controller.beginReply(pin: result.index)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel("\(OverlayChrome.replyAction) to note \(result.index)")
            }
        }
    }

    private func annotationID(for index: Int) -> UUID? {
        controller.annotations.first { $0.index == index }?.id
    }
}

/// A row's badge: the pin's number, a spinner while the agent has it, or its outcome's glyph, the
/// same states as the badge on the frozen screen. A filled circle in the list's own colors, since
/// the overlay's white badge would vanish on a light sheet.
private struct NoteBadge: View {
    let number: Int
    let mark: SentPinMark

    var body: some View {
        Group {
            switch mark {
            case .number:
                Text("\(number)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            case .progress:
                ProgressView()
                    .controlSize(.mini)
            case .symbol(let name, let tone):
                Image(systemName: name)
                    .font(.system(size: SentPinBadge.glyphSize, weight: .bold))
                    .foregroundStyle(Self.color(for: tone))
            }
        }
        .frame(width: AnnotateStyle.badgeSize, height: AnnotateStyle.badgeSize)
        .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
        .animation(SentPinBadge.changeAnimation, value: mark)
        .accessibilityHidden(true)
    }

    private static func color(for tone: PinOutcome.Tone) -> Color {
        switch tone {
        case .neutral: .primary
        case .success: Color(uiColor: .systemGreen)
        case .muted: Color(uiColor: .systemGray)
        case .attention: Color(uiColor: .systemOrange)
        }
    }
}
#endif
