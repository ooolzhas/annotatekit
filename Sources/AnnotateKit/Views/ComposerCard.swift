// The comment card for the open pin (Figma 9272:16847 empty · 9272:16929 typed · 9272:17011 with
// attachments): an optional strip of 64pt reference-image thumbnails with white remove badges,
// the comment field, and the paperclip / intent chip / × / ↑ row. The intent chip (no Figma
// frame) picks what the user wants done with the pin (Fix, Question, Approve, Move) and the
// placeholder follows it. It only lays itself out at the width it is given; OverlayRoot docks it
// to the keyboard and adds the 8pt inset. Return and ↑ save through the controller, which decides
// via `chrome` whether the comment can be submitted (Approve may be saved with no text).

#if DEBUG && canImport(UIKit)
import AnnotateCore
import PhotosUI
import SwiftUI

struct ComposerCard: View {
    let controller: AnnotateController
    let draft: AnnotateController.Draft

    @FocusState private var isFocused: Bool
    @State private var pickerItems: [PhotosPickerItem] = []

    /// Picked images are downscaled to this longest side before they are held in memory; the
    /// bundle stores them as JPEGs and a reference image never needs more.
    private static let maxImageDimension: CGFloat = 2048

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !draft.images.isEmpty {
                attachmentStrip
            }

            // 9272:16855 / 9272:17029 — px 20, py 16, Loose Leading/Body/Regular (17/24)
            TextField("", text: commentBinding, axis: .vertical)
                .font(.body.leading(.loose))
                .foregroundStyle(.primary)
                // Caps growth so the card doesn't climb over the drawing area (gap: Figma shows one line)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .submitLabel(.return)
                // iOS 26 delivers Return in a vertical field as a submit (no newline, keyboard
                // dismissed); earlier versions insert "\n", which `commentBinding` handles
                .onSubmit {
                    if case .composing(canSubmit: true) = controller.chrome {
                        controller.submitDraft()
                    } else {
                        // Nothing to save yet: keep the keyboard up so the card stays docked
                        isFocused = true
                    }
                }
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
        // Glass alone isn't hit-testable: without this, a tap that misses a button falls through
        // to the frozen screen and starts a new pin. A tap on the card focuses the comment instead.
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onTapGesture { isFocused = true }
        .onAppear { isFocused = true }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            let draftID = draft.annotation.id
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(Self.downscaled(image, maxDimension: Self.maxImageDimension))
                    }
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

    /// Before iOS 26 a vertical-axis TextField inserts a newline on Return instead of firing
    /// onSubmit. A Return keypress is the old text plus exactly one "\n" at the caret (anywhere, not
    /// only the end): that submits the old text. Any other newline (pasted multi-line text) becomes
    /// a space and is kept.
    private var commentBinding: Binding<String> {
        Binding(
            get: { controller.commentText },
            set: { [controller, id = draft.annotation.id] text in
                let old = controller.commentText
                let isReturn = text.count == old.count + 1
                    && text.replacingOccurrences(of: "\n", with: "") == old
                if isReturn {
                    controller.setComment(old, forDraft: id)
                    controller.submitDraft()
                } else {
                    let flattened = text.replacingOccurrences(of: "\n", with: " ")
                    controller.setComment(flattened, forDraft: id)
                }
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
            HStack(spacing: 6) {
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

            HStack(spacing: 6) {
                // 9257:13397/13398
                CircleIconButton(systemName: "xmark") { controller.discardDraft() }
                submitButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    /// No Figma: derived chip. Same 44pt height and 5% fill as `CircleIcon` `.plain`, stretched to
    /// a capsule around the intent title so the current choice reads without opening the menu.
    private static let chipHorizontalPadding: CGFloat = 14

    /// Menu of every intent; picking one stores it on the draft through the controller, which
    /// also lets `chrome` allow an empty Approve.
    private var intentChip: some View {
        let intent = intent
        return Menu {
            ForEach(AnnotationIntent.allCases, id: \.self) { option in
                Button {
                    controller.setIntent(option)
                } label: {
                    Label {
                        Text(option.title)
                        Text(option.detail)
                    } icon: {
                        Image(systemName: option.symbol)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(intent.title)
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.chipHorizontalPadding)
            .frame(height: CircleIcon.size)
            .background(Capsule().fill(Color.primary.opacity(CircleIcon.fillOpacity)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Intent, \(intent.title)")
    }

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
            controller.submitDraft()
        }
        .disabled(!canSubmit)
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

    /// 9272:17019 — `flex gap-[8px] items-end pt-[16px] px-[16px]`.
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
        // Four 64pt thumbnails plus gaps fit the card, so the strip never needs to scroll; don't
        // let it rubber-band thumbnails into the card's rounded corners
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func thumbnail(_ image: AnnotateController.AttachedImage) -> some View {
        Image(uiImage: image.image)
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

    /// Fits `image` inside `maxDimension` on its longest side, keeping the aspect ratio. Renders
    /// at scale 1 in 8-bit sRGB (BundleRenderer.format) so the size in points is the pixel size.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxDimension, longest > 0 else { return image }
        let factor = maxDimension / longest
        let size = CGSize(
            width: (image.size.width * image.scale * factor).rounded(),
            height: (image.size.height * image.scale * factor).rounded()
        )
        return UIGraphicsImageRenderer(size: size, format: BundleRenderer.format(scale: 1, opaque: true)).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
