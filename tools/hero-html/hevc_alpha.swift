// Encodes a numbered PNG sequence (RGBA) to an HEVC-with-alpha .mov, the one transparent video format Safari plays.
// ffmpeg's VideoToolbox wrapper drops the alpha plane, so this goes through AVAssetWriter directly.
// usage: hevc_alpha <frames-dir> <fps> <height> <out.mov>
import AVFoundation
import AppKit
import VideoToolbox

let args = CommandLine.arguments
guard args.count == 5, let fps = Int32(args[2]), let outH = Int(args[3]) else { fatalError("usage: hevc_alpha <frames-dir> <fps> <height> <out.mov>") }
let files = try FileManager.default.contentsOfDirectory(atPath: args[1]).filter { $0.hasSuffix(".png") }.sorted()
let first = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[1] + "/" + files[0])))!
let outW = Int((Double(first.pixelsWide) * Double(outH) / Double(first.pixelsHigh) / 2).rounded()) * 2
try? FileManager.default.removeItem(atPath: args[4])
let writer = try AVAssetWriter(url: URL(fileURLWithPath: args[4]), fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
    AVVideoWidthKey: outW, AVVideoHeightKey: outH,
    // Tagged BT.709 like the VP9 file, so browsers don't guess the matrix (untagged greys shift between players)
    AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000, AVVideoExpectedSourceFrameRateKey: fps,
                                      kVTCompressionPropertyKey_TargetQualityForAlpha as String: 0.9],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: outW, kCVPixelBufferHeightKey as String: outH,
])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
for (i, f) in files.enumerated() {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    let rep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[1] + "/" + f)))!
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!),
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: outW, height: outH))
    ctx.interpolationQuality = .high
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
}
input.markAsFinished()
await writer.finishWriting()
print(writer.status == .completed ? "wrote \(args[4]) \(outW)x\(outH) \(files.count) frames" : "failed: \(String(describing: writer.error))")
