// The comment card for the open pin (Figma 9257:13387): an optional strip of attached reference
// images, the comment field, and the paperclip / × / ↑ row. It only lays itself out at the width
// it is given; OverlayRoot docks it to the keyboard and adds the 8pt inset. Return and ↑ save
// through the controller, which decides via `chrome` whether the comment can be submitted.

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

            // 9257:13391 — px 24, py 20, Loose Leading/Body/Regular (17/24)
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
                .accessibilityHint(OverlayChrome.placeholder)
                .overlay(alignment: .topLeading) { placeholder }
                .padding(.horizontal, 24)
                // Figma centers the 17pt glyphs in a 24pt line; SwiftUI puts the extra leading
                // below, so shift 2pt down (22 + 18 keeps the 20 + 20 card height)
                .padding(.top, 22)
                .padding(.bottom, 18)

            buttonRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .annotateGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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

    /// 9257:13392 — "Describe the change" at 50% opacity. Drawn over the field because iOS 26
    /// ignores `prompt:` styling and renders the system placeholder color instead.
    @ViewBuilder
    private var placeholder: some View {
        if controller.commentText.isEmpty {
            Text(OverlayChrome.placeholder)
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
    private var buttonRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // 9257:13394/13395
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(remaining, 1), matching: .images) {
                // At the attachment cap the picker is disabled; dim it like ↑ so it reads disabled
                CircleIcon(systemName: "paperclip", style: remaining == 0 ? .dimmed : .plain)
            }
            .buttonStyle(ChromeButtonStyle())
            .disabled(remaining == 0)
            .accessibilityLabel("Attach image")

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

    // MARK: - Attachments (gap design: no Figma frame)

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(draft.images) { image in
                    thumbnail(image)
                }
            }
            // Room above the thumbnails for the remove button's -6pt offset so it isn't clipped
            .padding(.top, 6)
            .padding(.horizontal, 16)
            // 10 + the 6 above = the 16pt top gap (gap design)
            .padding(.top, 10)
        }
    }

    private func thumbnail(_ image: AnnotateController.AttachedImage) -> some View {
        Image(uiImage: image.image)
            .resizable()
            .scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    controller.removeAttachment(image.id)
                } label: {
                    // The 22pt visual sits at the thumbnail's top-trailing corner + (6, -6),
                    // overhanging it; the 32×32 hit area is centered on that offset visual
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove image")
                // Lay out at the 22pt visual's size (the 32pt hit box is 5pt larger per side), so
                // the circle itself aligns .topTrailing to the thumbnail, then offset it to
                // corner + (6, -6). The hit area overflows layout but stays hit-testable.
                .padding(-5)
                .offset(x: 6, y: -6)
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
