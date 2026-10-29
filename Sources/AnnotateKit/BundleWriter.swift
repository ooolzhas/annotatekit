// The off-main half of Send. The controller snapshots everything into a SendJob on the main actor
// (captures, pins, device info, destination); `BundleRenderer.write` then renders the 1x and
// annotated screens and per-pin crops, PNG-encodes them, JPEG-encodes each pin's reference-image
// attachments into `attachments/`, renders the prompt at the job's `PromptDetail`, writes the bundle and prunes old sessions —
// all on a background task, so the overlay dismisses instantly.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import UIKit

/// `@unchecked`: the only non-Sendable members are UIImages, which are immutable and documented
/// safe to use from any thread.
struct SendJob: @unchecked Sendable {
    struct Capture {
        let index: Int
        let capturedAt: Date
        let image: UIImage
        let elements: [ScreenElement]
    }

    let sessionID: String
    let app: AppInfo
    let device: DeviceInfo
    let captures: [Capture]
    let annotations: [Annotation]
    let outputDirectory: URL
    let completionNote: String?
    /// How much the prompt says; the app's `AnnotateOptions.promptDetail`.
    let promptDetail: PromptDetail
    let includesHiRes: Bool
    let keepSessions: Int
    let cropPadding: CGFloat
    /// Reference images per pin id, in the order picked.
    let attachments: [UUID: [UIImage]]
}

struct SendOutcome: Sendable {
    let prompt: String
    let pinCount: Int
    /// Set when the bundle couldn't be written; the prompt is still usable.
    let error: String?
}

extension BundleRenderer {
    /// JPEG quality for reference-image attachments (plan value): photos stay small, detail stays legible.
    private static let attachmentQuality: CGFloat = 0.85

    /// `progress` gets how many notes are written so far after each one, off the main thread; the
    /// hint line counts them ("Sending notes · 1/4").
    static func write(_ job: SendJob, progress: @Sendable (Int) -> Void = { _ in }) -> SendOutcome {
        /// Bundle-relative path → encoded file. PNGs for screens/crops, JPEGs for attachments.
        var images: [String: Data] = [:]
        var annotations = job.annotations
        var screens: [Screen] = []
        var written = 0

        for capture in job.captures {
            let positions = annotations.indices.filter { annotations[$0].screen == capture.index }
            guard !positions.isEmpty else { continue }
            var screen = Screen(
                index: capture.index,
                capturedAt: capture.capturedAt,
                size: AnnotationSize(capture.image.size),
                elements: capture.elements
            )

            let oneX = rescaled(capture.image, to: 1)
            if let data = oneX.pngData() {
                let path = "screens/\(capture.index).png"
                images[path] = data
                screen.image = path
            }
            if let data = annotatedScreenshot(oneX, annotations: positions.map { annotations[$0] }).pngData() {
                let path = "screens/\(capture.index)-annotated.png"
                images[path] = data
                screen.annotatedImage = path
            }
            let scale = Int(capture.image.scale.rounded())
            if job.includesHiRes, scale > 1, let data = capture.image.pngData() {
                let path = "screens/\(capture.index)@\(scale)x.png"
                images[path] = data
                screen.hiResImage = path
            }
            for position in positions {
                // A pin is written once its crop is encoded, or found to have none
                defer {
                    written += 1
                    progress(written)
                }
                let pin = annotations[position]
                guard let crop = crop(pin, from: capture.image, padding: job.cropPadding), let data = crop.pngData() else { continue }
                let path = "crops/\(pin.index).png"
                images[path] = data
                annotations[position].crop = path
            }
            screens.append(screen)
        }

        writeAttachments(job.attachments, into: &images, annotations: &annotations)

        let session = AnnotationSession(
            id: job.sessionID,
            createdAt: Date(),
            app: job.app,
            device: job.device,
            screens: screens,
            annotations: annotations
        )
        let sessionDirectory = SessionInbox.sessionDirectory(session.id, in: job.outputDirectory)
        let prompt = PromptRenderer.render(session, sessionPath: sessionDirectory.path, completion: job.completionNote, detail: job.promptDetail)

        do {
            try SessionWriter.write(SessionBundle(session: session, images: images), prompt: prompt, to: job.outputDirectory)
        } catch {
            return SendOutcome(prompt: prompt, pinCount: annotations.count, error: error.localizedDescription)
        }
        SessionInbox.prune(keeping: max(job.keepSessions, 1), in: job.outputDirectory)
        return SendOutcome(prompt: prompt, pinCount: annotations.count, error: nil)
    }

    /// JPEG-encodes each pin's picked images to `attachments/<pin.index>-<n>.jpg` (n from 1, in pick
    /// order) and records the written paths on the pin. Images that fail to encode are skipped; a pin
    /// with nothing written keeps `attachments == nil`.
    private static func writeAttachments(
        _ attachments: [UUID: [UIImage]],
        into images: inout [String: Data],
        annotations: inout [Annotation]
    ) {
        for position in annotations.indices {
            let pin = annotations[position]
            guard let picked = attachments[pin.id], !picked.isEmpty else { continue }
            var paths: [String] = []
            for (offset, image) in picked.enumerated() {
                guard let data = image.jpegData(compressionQuality: attachmentQuality) else { continue }
                let path = "attachments/\(pin.index)-\(offset + 1).jpg"
                images[path] = data
                paths.append(path)
            }
            if !paths.isEmpty { annotations[position].attachments = paths }
        }
    }
}
#endif
