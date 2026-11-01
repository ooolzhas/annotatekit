// The comment card for the open pin (Figma 9276:27099 empty · 9276:27185 typed · 9276:27272 with
// attachments · 9276:27369 quoting): an optional strip with the element's own text quoted like a
// message being replied to (236pt wide, two lines at most) and 64pt reference-image thumbnails with
// white remove badges, the comment field, and the paperclip / intent chip / undo / redo / ↑ row.
// The intent chip (9276:27109 shows "Fix") opens our own dropdown above it to pick what the user wants
// done with the pin (Fix, Question), and the placeholder follows it. The dropdown is SwiftUI inside the
// overlay rather than a system menu: the system one is drawn by UIKit outside this view tree, where the
// frozen screen's touch-down drag gesture could take a real finger's tap on an item (seen on
// iOS 27 devices; it never reproduced on simulators). Undo and redo step through the strokes drawn since the card opened
// (StrokeHistory); with nothing left to undo, undo turns into × and discards the pin, and redo dims
// with nothing to redo. It only lays itself out at the width it is given; OverlayRoot docks it
// to the keyboard (8pt insets) or, with no keyboard, where the review bar sits (34pt insets). ↑ saves through the controller, which decides via
// `chrome` whether the comment can be submitted (it needs text); Return types a
// newline. A new drawing opens the card without the keyboard so the next stroke has the screen.

#if DEBUG && canImport(UIKit)
#if canImport(AnnotateCore) // the CocoaPods build compiles AnnotateCore into this module
import AnnotateCore
#endif
import ImageIO
import PhotosUI
import SwiftUI

struct ComposerCard: View {
    let controller: AnnotateController
    let draft: AnnotateController.Draft

    @FocusState private var isFocused: Bool
    /// Pixels per point, for sizing the tiles' thumbnails.
    @Environment(\.displayScale) private var displayScale
    @State private var pickerItems: [PhotosPickerItem] = []
    /// The intent dropdown is open above the chip.
    @State private var isPickingIntent = false
    /// ↑ was tapped with the keyboard up: the card is hidden, waiting for the keyboard to slide away.
    /// Set while the card waits for the keyboard to start sliding away before it leaves (LeaveAfterKeyboard).
    @State private var leaving: (() -> Void)?

    /// Picked images are downscaled to this longest side before they are held in memory; the
    /// bundle stores them as JPEGs and a reference image never needs more.
    private static let maxImageDimension: CGFloat = 2048

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if quote != nil || !draft.images.isEmpty {
                attachmentStrip
            }

            // 9272:16855 / 9272:17029 — px 20, py 16, Loose Leading/Body/Regular (17/24)
            TextField("", text: commentBinding, axis: .vertical)
                .font(.body.leading(.loose))
                .foregroundStyle(.primary)
                // Caps growth so the card doesn't climb over the drawing area (gap: Figma shows one line)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("Comment")
                // The drawn placeholder is hidden from VoiceOver; announce it as the hint instead
                .accessibilityHint(intent.placeholder)
                .overlay(alignment: .topLeading) { placeholder }
                .padding(.horizontal, 20)
                // Figma centers the 17pt glyphs in a 24pt line; SwiftUI puts the extra leading
                // below, so shift 2pt down (18 + 14 keeps the 16 + 16 card height)
                .padding(.top, 18)
                .padding(.bottom, 14)

            buttonRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .annotateGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: true)
        // Glass alone isn't hit-testable: without a hit shape, a tap that misses a button falls through
        // to the frozen screen and starts a new pin. The shape sits on a background rather than the
        // card itself, so the intent dropdown, which rises above the card's top edge, still takes taps.
        // A tap on the card outside a control closes the dropdown; the comment field focuses itself.
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .onTapGesture { closeIntentPicker() }
        }
        // Outside the glass: glass only takes touches inside its own shape, and the dropdown rises
        // past the card's top edge. Its bottom-leading corner sits over the chip's top-leading one,
        // lifted `pickerGap`; an offset moves the hit area along with the drawing
        .overlay(alignment: .bottomLeading) {
            if isPickingIntent {
                intentDropdown(current: intent)
                    .offset(x: Self.pickerLeading, y: -Self.pickerLift)
                    .transition(.scale(scale: Self.pickerHiddenScale, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .modifier(LeaveAfterKeyboard(leave: $leaving))
        .onAppear { isFocused = !opensWithoutKeyboard }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            let draftID = draft.annotation.id
            let maxDimension = Self.maxImageDimension
            let tilePixels = Self.thumbnailSize * displayScale
            Task {
                var images: [AnnotateController.AttachedImage] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    // Detached: this Task inherits the main actor, where decoding and redrawing a
                    // 12–48 MP photo froze the card for 100–400 ms
                    let attached = await Task.detached(priority: .userInitiated) {
                        ComposerCard.prepareAttachment(data, maxDimension: maxDimension, tilePixels: tilePixels)
                    }.value
                    if let attached { images.append(attached) }
                }
                // Loading outlives this card; images belong to the pin they were picked for
                guard controller.draft?.annotation.id == draftID else { return }
                controller.addAttachments(images)
                // The picker sheet took focus; bring the keyboard back so the card stays docked
                isFocused = true
            }
        }
    }

    // MARK: - Text

    /// A drawing in progress: more strokes usually follow, and the keyboard would cover the lower
    /// half of the screen. A tap on the card brings it up.
    private var opensWithoutKeyboard: Bool {
        draft.isNew && draft.annotation.kind == .sketch
    }

    /// The pin's intent; drafts from before intents existed have none, which means Fix.
    private var intent: AnnotationIntent {
        draft.annotation.intent ?? .fix
    }

    /// 9257:13392 — "Describe the change" at 50% opacity (Fix); other intents swap the copy via
    /// `AnnotationIntent.placeholder`. Drawn over the field because iOS 26 ignores `prompt:`
    /// styling and renders the system placeholder color instead.
    @ViewBuilder
    private var placeholder: some View {
        if controller.commentText.isEmpty {
            Text(intent.placeholder)
                .font(.body.leading(.loose))
                .foregroundStyle(.primary.opacity(0.5))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Newlines are kept (the prompt renders a multi-line comment line by line). Writes are tagged
    /// with the draft they were typed into, so text arriving late can't land on another pin.
    private var commentBinding: Binding<String> {
        Binding(
            get: { controller.commentText },
            set: { [controller, id = draft.annotation.id] text in
                controller.setComment(text, forDraft: id)
            }
        )
    }

    // MARK: - Buttons

    private var remaining: Int {
        AnnotateController.maxAttachments - draft.images.count
    }

    /// 9257:13393 — items-end, justify-between, pb 8, px 8; right group gap 6 (9257:13396).
    /// No Figma: the left group (paperclip + intent chip) reuses the right group's 6pt gap.
    private var buttonRow: some View {
        // PhotosPicker's label closure is Sendable: read main-actor state before it
        let remaining = remaining
        let paperclipStyle: CircleIcon.Style = remaining == 0 ? .dimmed : .plain
        return HStack(alignment: .bottom, spacing: 0) {
            HStack(spacing: Self.rowGroupSpacing) {
                // 9257:13394/13395
                PhotosPicker(selection: $pickerItems, maxSelectionCount: max(remaining, 1), matching: .images) {
                    // At the attachment cap the picker is disabled; dim it like ↑ so it reads disabled
                    CircleIcon(systemName: "paperclip", style: paperclipStyle)
                }
                .buttonStyle(ChromeButtonStyle())
                .disabled(remaining == 0)
                .accessibilityLabel("Attach image")

                intentChip
            }

            Spacer(minLength: 0)

            HStack(spacing: Self.rowGroupSpacing) {
                // No Figma: undo / redo sit where Figma's × was (9257:13397/13398, design choice), and
                // undo turns back into that × once there's nothing left to undo
                undoOrDiscardButton
                CircleIconButton(
                    systemName: "arrow.uturn.forward",
                    style: draft.history.canRedo ? .plain : .dimmed
                ) { controller.redo() }
                .disabled(!draft.history.canRedo)
                submitButton
            }
        }
        .padding(.horizontal, Self.rowInset)
        .padding(.bottom, Self.rowInset)
    }

    /// Undo while there are strokes to take back; at the state the card opened with (a new drawing's
    /// first stroke, a tap or hold pin, a reopened pin as saved) it's × and discards the pin instead.
    private var undoOrDiscardButton: some View {
        let canUndo = draft.history.canUndo
        return CircleIconButton(
            systemName: canUndo ? "arrow.uturn.backward" : "xmark",
            label: canUndo ? nil : (draft.isNew ? "Discard pin" : "Delete pin")
        ) {
            if canUndo {
                controller.undo()
            } else {
                leave { controller.discardDraft() }
            }
        }
        // Four times the system speed (design choice): the swap reads as a state change, not an animation
        .contentTransition(.symbolEffect(.replace, options: .speed(Self.symbolSwapSpeed)))
    }

    /// How much faster than the system default undo and × swap glyphs.
    private static let symbolSwapSpeed: Double = 4

    /// Figma 9276:27109: `px-[12px] w-[65px] h-[44px]`, 5% fill like `CircleIcon` `.plain`. 65 is the
    /// width "Fix" draws at, so it is the minimum and longer titles grow the capsule.
    private static let chipHorizontalPadding: CGFloat = 12
    private static let chipMinWidth: CGFloat = 65
    /// No Figma frame (design choice): the up / down chevron that marks the chip as a menu, 4pt after the
    /// title and smaller than it so the intent reads first.
    private static let chipChevronSpacing: CGFloat = 4
    private static let chipChevronSize: CGFloat = 11

    /// The chip toggles the dropdown above it; picking an intent stores it on the draft through the
    /// controller and closes the dropdown.
    private var intentChip: some View {
        let intent = intent
        return Button {
            withAnimation(Self.pickerAnimation) { isPickingIntent.toggle() }
        } label: {
            // 9276:27110 — SF Pro Medium 17 / 22; the chevron is an addition
            HStack(spacing: Self.chipChevronSpacing) {
                Text(intent.title)
                    .font(.system(size: 17, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: Self.chipChevronSize, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.chipHorizontalPadding)
            .frame(minWidth: Self.chipMinWidth)
            .frame(height: CircleIcon.size)
            .background(Capsule().fill(Color.primary.opacity(CircleIcon.fillOpacity)))
            .contentShape(Capsule())
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Intent, \(intent.title)")
        .accessibilityHint("Choose what to do with this note")
    }

    /// No Figma: every intent as a row (symbol, title, what it asks the agent for), the current one
    /// checked, on glass like the card.
    private func intentDropdown(current: AnnotationIntent) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.pickerRadius, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(AnnotationIntent.allCases, id: \.self) { option in
                Button {
                    controller.setIntent(option)
                    closeIntentPicker()
                } label: {
                    HStack(spacing: Self.pickerRowSpacing) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 17))
                            .frame(width: Self.pickerSymbolWidth)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.body)
                            Text(option.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if option == current {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Self.pickerRowHorizontalPadding)
                    .padding(.vertical, Self.pickerRowVerticalPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityAddTraits(option == current ? .isSelected : [])
            }
        }
        .padding(.vertical, Self.pickerVerticalPadding)
        .frame(width: Self.pickerWidth)
        .annotateGlass(in: shape)
        .contentShape(shape)
    }

    private func closeIntentPicker() {
        guard isPickingIntent else { return }
        withAnimation(Self.pickerAnimation) { isPickingIntent = false }
    }

    /// Intent dropdown geometry (no Figma, derived): wide enough for "Explain it, don't edit" on one
    /// line, 8pt above the chip, rows like a system menu's.
    private static let pickerWidth: CGFloat = 248
    private static let pickerGap: CGFloat = 8
    private static let pickerRadius: CGFloat = 24
    private static let pickerVerticalPadding: CGFloat = 6
    private static let pickerRowHorizontalPadding: CGFloat = 16
    private static let pickerRowVerticalPadding: CGFloat = 10
    private static let pickerRowSpacing: CGFloat = 12
    private static let pickerSymbolWidth: CGFloat = 24
    private static let pickerHiddenScale: CGFloat = 0.9
    /// The chip's leading edge from the card's: the row's 8pt inset, the paperclip and the 6pt gap.
    private static let pickerLeading: CGFloat = rowInset + CircleIcon.size + rowGroupSpacing
    /// From the card's bottom to `pickerGap` above the chip: the row's 8pt inset and the chip.
    private static let pickerLift: CGFloat = rowInset + CircleIcon.size + pickerGap
    /// 9257:13393 — the button row's `pb-8 px-8`, and the 6pt gap inside each group.
    private static let rowInset: CGFloat = 8
    private static let rowGroupSpacing: CGFloat = 6
    private static let pickerAnimation: Animation = .snappy(duration: 0.2)

    /// 9257:13399 (empty, dimmed glyph) · 9257:13480 (typed, blue). The state comes from
    /// `chrome`, never from the text. Only `.dimmed` dims; `.disabled` just blocks the tap
    /// (submitDraft no-ops anyway when it can't submit).
    private var submitButton: some View {
        let canSubmit: Bool
        if case .composing(let value) = controller.chrome {
            canSubmit = value
        } else {
            canSubmit = false
        }
        return CircleIconButton(systemName: "arrow.up", style: canSubmit ? .prominent : .dimmed) {
            leave { controller.submitDraft() }
        }
        .disabled(!canSubmit)
    }

    /// Runs `action`, which takes the card out, right away with no keyboard up; otherwise lets the
    /// keyboard go first so it keeps its slide (LeaveAfterKeyboard).
    private func leave(_ action: @escaping () -> Void) {
        guard controller.isKeyboardUp else {
            action()
            return
        }
        // Pin the card where it is, so it leaves in place rather than riding the keyboard down
        controller.holdCardDock()
        leaving = { [controller] in
            action()
            controller.releaseCardDock()
        }
        isFocused = false
    }

    // MARK: - Attachments (9272:17019)

    /// 9272:17020 — thumbnail side.
    private static let thumbnailSize: CGFloat = 64
    /// 9272:17020 — `rounded-[16px]` thumbnail clip.
    private static let thumbnailRadius: CGFloat = 16
    /// 9272:17023 — remove badge diameter.
    private static let badgeSize: CGFloat = 20
    /// 9272:17023 — the badge center sits this far inside the thumbnail's top-right corner
    /// (badge at left 66 / top 10 in the strip, thumbnail at 16…80), so it overhangs 6pt.
    private static let badgeInset: CGFloat = 4
    /// The remove badge is too small to hit reliably; the tap target is this square around it.
    private static let badgeHitSize: CGFloat = 32

    /// How far the badge pokes past the thumbnail's top and right edges (20 / 2 − 4 = 6).
    private static var badgeOverhang: CGFloat { badgeSize / 2 - badgeInset }

    /// Figma 9378:6016 / 9378:5922: `w-[236px] px-[16px]`; the height hugs the text.
    private static let quoteWidth: CGFloat = 236
    private static let quoteHorizontalPadding: CGFloat = 16
    /// Figma `py-[12px]`: one 20pt line makes the box 44pt (9378:6016), two make it 64pt (9378:5922).
    private static let quoteVerticalPadding: CGFloat = 12
    /// Figma `opacity-75` on the quoted lines (9276:27375).
    private static let quoteOpacity: Double = 0.75

    /// The selected element's own text, quoted ahead of any images; nil when there's none.
    private var quote: String? {
        draft.annotation.quotedText
    }

    /// 9272:17019 — `flex gap-[8px] items-end pt-[16px] px-[16px]`.
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Figma `items-end`: a two-line quote is taller than a thumbnail, and they share a bottom
            HStack(alignment: .bottom, spacing: 8) {
                if let quote {
                    quoteBox(quote)
                }
                // The remove badge's 32pt hit box reaches 12pt past its thumbnail's right edge,
                // over the 8pt gap and 4pt into the next thumbnail. Later HStack siblings draw
                // on top by default and would take that strip, so stack earlier thumbnails above
                // later ones to keep each badge's whole hit box tappable
                ForEach(Array(draft.images.enumerated()), id: \.element.id) { index, image in
                    thumbnail(image)
                        .zIndex(Double(draft.images.count - index))
                }
            }
            // Room above the thumbnails for the badge's 6pt overhang, inside the ScrollView so
            // the badge isn't clipped by it
            .padding(.top, Self.badgeOverhang)
            .padding(.horizontal, 16)
            // 10 + the 6pt room above = Figma's 16pt from the card top to the thumbnails
            .padding(.top, 16 - Self.badgeOverhang)
        }
        // Four 64pt thumbnails plus gaps fit the card, so without a quote the strip never needs to
        // scroll; don't let it rubber-band thumbnails into the card's rounded corners
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// The element's text in a box with a thumbnail's radius and fill, like the message a reply
    /// quotes. Figma 9378:6016 / 9378:5922: Loose Leading/Footnote (13 / 20) at 75%, two lines, then
    /// it truncates. The box hugs the text (44pt for one line, 64pt for two), so the text is
    /// vertically centered by its equal padding.
    private func quoteBox(_ text: String) -> some View {
        Text(text)
            .font(.footnote.leading(.loose))
            .foregroundStyle(.primary.opacity(Self.quoteOpacity))
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.horizontal, Self.quoteHorizontalPadding)
            .padding(.vertical, Self.quoteVerticalPadding)
            .frame(width: Self.quoteWidth, alignment: .leading)
            .background(
                Color.primary.opacity(CircleIcon.fillOpacity),
                in: RoundedRectangle(cornerRadius: Self.thumbnailRadius, style: .continuous)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Quoting \(text)")
    }

    private func thumbnail(_ image: AnnotateController.AttachedImage) -> some View {
        Image(uiImage: image.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: Self.thumbnailRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    controller.removeAttachment(image.id)
                } label: {
                    // 9272:17023 — white 20pt badge, black SF Pro Semibold 11 xmark. Its center
                    // sits 4pt inside the thumbnail's top-right corner, overhanging it 6pt up and
                    // right; the 32×32 hit area is centered on the badge
                    Circle()
                        .fill(Color.white)
                        .frame(width: Self.badgeSize, height: Self.badgeSize)
                        .overlay {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        .frame(width: Self.badgeHitSize, height: Self.badgeHitSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove image")
                // Lay out at the 20pt badge's size (the 32pt hit box is 6pt larger per side), so
                // the circle itself aligns .topTrailing to the thumbnail (center at corner
                // + (−10, +10)), then offset by 6 to reach corner + (−4, +4). The hit area
                // overflows layout but stays hit-testable.
                .padding(-(Self.badgeHitSize - Self.badgeSize) / 2)
                .offset(x: Self.badgeOverhang, y: -Self.badgeOverhang)
            }
    }

    /// Decodes a picked photo straight to `maxDimension` on its longest side with ImageIO, which
    /// never holds the full-size bitmap and applies the EXIF orientation, plus a copy whose shorter
    /// side covers `tilePixels` for the tile. Scale 1, so the size in points is the pixel size.
    /// Runs off the main actor.
    nonisolated private static func prepareAttachment(
        _ data: Data,
        maxDimension: CGFloat,
        tilePixels: CGFloat
    ) -> AnnotateController.AttachedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as [CFString: Any] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = UIImage(cgImage: decoded)
        return AnnotateController.AttachedImage(id: UUID(), image: image, thumbnail: tileThumbnail(of: image, tilePixels: tilePixels))
    }

    /// `image` scaled so its shorter side is `tilePixels` (the tile fills a square), or `image` itself
    /// when it is already that small. Drawn from the decoded copy, not the photo, so it costs a
    /// small redraw rather than a second decode.
    nonisolated private static func tileThumbnail(of image: UIImage, tilePixels: CGFloat) -> UIImage {
        let shorter = min(image.size.width, image.size.height)
        guard shorter > tilePixels, tilePixels > 0 else { return image }
        let factor = tilePixels / shorter
        let size = CGSize(width: (image.size.width * factor).rounded(), height: (image.size.height * factor).rounded())
        return UIGraphicsImageRenderer(size: size, format: BundleRenderer.format(scale: 1)).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
