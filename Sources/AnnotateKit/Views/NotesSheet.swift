// The note list behind the review bar's count (no Figma: owner request). A sheet that opens at a
// small detent and drags up to full height, with tags in a bar under its toolbar that pick what it lists:
// Current (pins waiting to be sent), In Progress, Resolved and Failed (the last Send's pins, sorted by
// `NoteFilter`, from the last Send and every earlier one of the last 48 hours, grouped by Send),
// each with its count. Current rows open on the comment card with a tap (pins on another
// screen can't open here, so they only list) and delete with a swipe (a trash icon, no label); Clear
// All (a trash icon) clears them after an alert asks. Sent rows show the same spinner / glyph / number as their badges, with
// Reply on a question of the last Send. A tag with nothing in it shows an empty state. Row copy comes from `PinResult`
// and `PinOutcome` in AnnotateCore.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct NotesSheet: View {
    let controller: AnnotateController

    @State private var detent: PresentationDetent = Self.compactDetent
    @State private var isConfirmingClear = false
    /// The tag picked by the user; nil until they pick one, so the sheet opens on the first tag with notes.
    @State private var pickedFilter: NoteFilter?

    /// The small detent the sheet opens at: the title, the tags and about two rows, so the frozen screen
    /// stays mostly visible. Dragging up gives the full-height list.
    static let compactDetent: PresentationDetent = .fraction(0.4)
    /// Badge to text gap, and title to subtitle gap.
    static let rowSpacing: CGFloat = 12
    static let textSpacing: CGFloat = 2
    /// Tags: 8pt apart, inset like the list's cards, snug under the toolbar.
    static let tagSpacing: CGFloat = 8
    static let tagBarHorizontalPadding: CGFloat = 16
    static let tagBarTopPadding: CGFloat = 4
    static let tagBarBottomPadding: CGFloat = 8
    /// Space between the tag bar and the first card.
    static let listTopMargin: CGFloat = 8
    static let tagChange: Animation = .snappy(duration: 0.2)

    var body: some View {
        let pending = PinResult.results(for: controller.annotations, statuses: [])
        // The last Send first, then earlier ones newest first, each in pin order. Grouping keeps that
        // order inside every tag. Only the last Send has a live delivery stage
        let sent = Dictionary(grouping: sentNotes) {
            NoteFilter.of($0.result.outcome, delivery: $0.stage)
        }
        let counts = Dictionary(uniqueKeysWithValues: NoteFilter.allCases.map { filter in
            (filter, filter == .current ? pending.count : sent[filter]?.count ?? 0)
        })
        let filter = pickedFilter ?? NoteFilter.initial(counts: counts)

        NavigationStack {
            List {
                if filter == .current {
                    ForEach(pending) { note in
                        pendingRow(note)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let id = annotationID(for: note.index) { controller.deleteNote(id) }
                                } label: {
                                    // Icon only (owner request); VoiceOver still hears the action
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel(OverlayChrome.clearAction)
                            }
                    }
                } else {
                    ForEach(Self.sends(sent[filter] ?? [])) { send in
                        Section {
                            ForEach(send.notes) { note in
                                sentRow(note)
                            }
                        } header: {
                            // No Figma (derived): "Sent 2 hours ago"
                            Text("Sent \(send.sentAt.formatted(.relative(presentation: .named)))")
                        }
                    }
                }
                // A row under the tags rather than an overlay on the list, which would sit on them
                if counts[filter] == 0 {
                    ContentUnavailableView {
                        Label(filter.emptyTitle, systemImage: Self.emptySymbol(filter))
                    } description: {
                        if filter == .current { Text(ReviewHint.gestures.headline) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            // The grouped list's own top inset doubled the gap under the tags
            .contentMargins(.top, Self.listTopMargin, for: .scrollContent)
            .tagBar {
                tags(selected: filter, counts: counts)
            }
            .navigationTitle(controller.reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if filter == .current, !pending.isEmpty {
                        // Just the icon (owner request); VoiceOver reads it as Clear All
                        Button(role: .destructive) {
                            isConfirmingClear = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                        .accessibilityLabel(OverlayChrome.clearAllTitle)
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
            // An alert in the middle of the screen (owner request), not a popover off the button
            .alert(OverlayChrome.clearTitle(pending.count), isPresented: $isConfirmingClear) {
                Button(OverlayChrome.clearAction, role: .destructive) {
                    controller.clearAll()
                    controller.closeNotes()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([Self.compactDetent, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Tags

    private func tags(selected: NoteFilter, counts: [NoteFilter: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.tagSpacing) {
                ForEach(NoteFilter.allCases, id: \.self) { filter in
                    NoteTag(filter: filter, count: counts[filter] ?? 0, isSelected: filter == selected) {
                        withAnimation(Self.tagChange) { pickedFilter = filter }
                    }
                }
            }
            .padding(.horizontal, Self.tagBarHorizontalPadding)
            .padding(.top, Self.tagBarTopPadding)
            .padding(.bottom, Self.tagBarBottomPadding)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private static func emptySymbol(_ filter: NoteFilter) -> String {
        switch filter {
        case .current: "note.text"
        case .inProgress: "hourglass"
        case .resolved: "checkmark.circle"
        case .failed: "xmark.circle"
        }
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
    private func sentRow(_ note: SentNote) -> some View {
        let result = note.result
        let outcome = result.outcome
        let mark = SentPinMark.resolve(outcome: outcome, delivery: note.isLatest ? controller.delivery : nil)
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

            // Replies go to the last Send, the one the agent is waiting on
            if outcome.isQuestion, note.isLatest {
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

    /// The last Send's notes, then every earlier Send's of the last 48 hours, newest first.
    private var sentNotes: [SentNote] {
        let latest = controller.lastSend.map { send in
            controller.pinResults.map {
                SentNote(sessionID: send.sessionID, sentAt: send.sentAt, result: $0,
                         stage: controller.lastSendStage, isLatest: true)
            }
        } ?? []
        let earlier = controller.history.flatMap { send in
            send.results.map {
                SentNote(sessionID: send.sessionID, sentAt: send.sentAt, result: $0, stage: send.stage, isLatest: false)
            }
        }
        return latest + earlier
    }

    /// `notes` split into one group per Send, keeping their order.
    private static func sends(_ notes: [SentNote]) -> [SendGroup] {
        var groups: [SendGroup] = []
        for note in notes {
            if groups.last?.sessionID == note.sessionID {
                groups[groups.count - 1].notes.append(note)
            } else {
                groups.append(SendGroup(sessionID: note.sessionID, sentAt: note.sentAt, notes: [note]))
            }
        }
        return groups
    }

    private func annotationID(for index: Int) -> UUID? {
        controller.annotations.first { $0.index == index }?.id
    }
}

/// One sent note: a pin of the last Send, or of an earlier one from the last 48 hours.
private struct SentNote: Identifiable {
    let sessionID: String
    let sentAt: Date
    let result: PinResult
    /// Where its Send got to (kept after the pill's hold), which files a note the agent never
    /// reported on (`NoteFilter.of`).
    let stage: DeliveryStage?
    /// The last Send: its delivery stage is live and its questions can be answered here.
    let isLatest: Bool

    var id: String { "\(sessionID)#\(result.index)" }
}

/// One Send's notes inside a tag, under a "Sent 2 hours ago" header.
private struct SendGroup: Identifiable {
    let sessionID: String
    let sentAt: Date
    var notes: [SentNote]

    var id: String { sessionID }
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
/// One tag: its title and count in a capsule, filled with the label color while picked.
private struct NoteTag: View {
    let filter: NoteFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    static let height: CGFloat = 32
    static let horizontalPadding: CGFloat = 12
    static let countSpacing: CGFloat = 4
    /// The count reads after the title, quieter.
    static let countOpacity: Double = 0.6
    /// The picked tag inverts the label colors. Explicit UIColors: `Color.primary` renders washed
    /// out to gray on the sheet's glass.
    static let selectedFill = Color(uiColor: .label)
    static let selectedText = Color(uiColor: .systemBackground)

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.countSpacing) {
                Text(filter.title)
                if count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .opacity(Self.countOpacity)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Self.selectedText : .primary)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: Self.height)
            .background(Capsule().fill(isSelected ? Self.selectedFill : Color(uiColor: .tertiarySystemFill)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(filter.title), \(count)" : filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
private extension View {
    /// The tags sit in a bar under the toolbar that stays put while the list scrolls: on iOS 26 a
    /// safe-area bar, which gets the system's scroll edge effect; before, an inset on the bar material.
    @ViewBuilder
    func tagBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top) { content() }
        } else {
            safeAreaInset(edge: .top, spacing: 0) { content().background(.bar) }
        }
        #else
        safeAreaInset(edge: .top, spacing: 0) { content().background(.bar) }
        #endif
    }
}
#endif
