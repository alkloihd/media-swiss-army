//
//  StillVideoBaker.swift
//  VideoCompressor
//
//  Converts a single still image (HEIC / JPEG / PNG) into a tiny .mov file
//  showing that image for `duration` seconds. Used by `StitchExporter` so
//  AVMutableComposition (which only accepts AVAssetTracks from URL assets)
//  can include still-image clips in a stitched output.
//
//  Implementation:
//   - Decode the source image via ImageIO
//   - Resize to a reasonable max (1080×1920) to keep the temp file small
//   - Use AVAssetWriter + AVAssetWriterInputPixelBufferAdaptor to write
//     a 30 fps H.264 video where every frame is the same buffer
//   - Result file lives in NSTemporaryDirectory, caller cleans up
//

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

actor StillVideoBaker {

    /// Canvas the still gets drawn onto. We pick a sensible default that
    /// covers both portrait and landscape stitch canvases without being
    /// gratuitously large (each pixel costs encode time even for a static
    /// frame).
    private let maxEdge: CGFloat = 1920

    /// Frame rate for the baked video. 30 is the iOS default and matches
    /// the rate the rest of the stitch composition runs at.
    private let frameRate: Int32 = 30

    /// Cleanly bake `still` to a temp .mov of `duration` seconds. The
    /// returned URL is the caller's to manage — `StitchExporter.buildPlan`
    /// tracks them and invalidates after the export finishes.
    func bake(still sourceURL: URL, duration: Double) async throws -> URL {
        guard duration > 0 else {
            throw BakeError.invalidDuration
        }

        // Load + decode the still.
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw BakeError.unreadableSource(sourceURL.lastPathComponent)
        }

        // Use the embedded thumbnail-extraction pipeline so we get a sized,
        // oriented image for cheap.
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOpts as CFDictionary
        ) else {
            throw BakeError.decodeFailed(sourceURL.lastPathComponent)
        }

        // Round to even dims — H.264 encoders reject odd dimensions and
        // `writer.startWriting()` returns false with a cryptic error (H5).
        let width = (cgImage.width / 2) * 2
        let height = (cgImage.height / 2) * 2
        guard width >= 16, height >= 16 else {
            throw BakeError.decodeFailed("\(sourceURL.lastPathComponent) too small (\(width)×\(height))")
        }

        // Output URL.
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillBakes", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)

        // Configure writer.
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoMaxKeyFrameIntervalKey: frameRate,  // I-frame each second
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(input) else {
            throw BakeError.writerSetupFailed("cannot add input")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw BakeError.writerSetupFailed(
                writer.error?.localizedDescription ?? "startWriting false"
            )
        }
        writer.startSession(atSourceTime: .zero)

        // Build a single CVPixelBuffer holding the still. Each early-throw
        // path BELOW must clean up the writer + outURL (Audit-2-F2 fix —
        // previously throwing without cancelWriting + removeItem would
        // leak the partially-started writer + an empty .mov).
        func bailWithError(_ err: BakeError) -> BakeError {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outURL)
            return err
        }
        guard let pool = adaptor.pixelBufferPool else {
            throw bailWithError(.writerSetupFailed("no pixel buffer pool"))
        }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw bailWithError(.writerSetupFailed("pixel buffer alloc failed (\(status))"))
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        // We unlock EXPLICITLY after draw — AVAssetWriterInputPixelBufferAdaptor
        // expects buffers unlocked before append. Apple sample code (Tech Note
        // QA1702) follows this pattern. A function-scope `defer` would hold
        // the lock across all appends and risks the encoder reading from a
        // locked IOSurface.
        guard let baseAddr = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            throw bailWithError(.writerSetupFailed("no base address"))
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // BGRA byte order with premultiplied first alpha matches kCVPixelFormatType_32BGRA.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddr,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            throw bailWithError(.writerSetupFailed("CGContext init failed"))
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        // Append frames at frameRate. Same buffer every time — encoder
        // deduplicates inter-frame predictions naturally so the file is small.
        //
        // Concurrency safety:
        // - `frame` is hoisted into a class box outside the closure; without
        //   this, requestMediaDataWhenReady's re-invocation reset `frame=0`
        //   each entry → continuation could resume twice → fatal.
        // - `done` flag guards against double-resume even if AVFoundation
        //   re-invokes the closure after markAsFinished() in a race.
        let totalFrames = max(1, Int(duration * Double(frameRate)))
        let queue = DispatchQueue(label: "still-bake.\(outURL.lastPathComponent)")
        let inputRef = input
        let adaptorRef = adaptor
        let counter = FrameCounter()
        let appendFailureBox = AppendFailureBox()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inputRef.requestMediaDataWhenReady(on: queue) {
                // Re-entry guard: AVFoundation may invoke this closure again
                // AFTER we've called markAsFinished. Bail on re-entry. This
                // check is OUTSIDE the inner while-loop (the previous version
                // was inside the loop and short-circuited frame 2+, leaving
                // the bake at a single frame — Audit-1-C1, 2026-05-03).
                if counter.isDone { return }
                while inputRef.isReadyForMoreMediaData {
                    let frame = counter.value
                    if frame >= totalFrames {
                        counter.markDone()
                        inputRef.markAsFinished()
                        if counter.tryClaimResume() { continuation.resume() }
                        return
                    }
                    let pts = CMTime(
                        value: CMTimeValue(frame),
                        timescale: CMTimeScale(self.frameRate)
                    )
                    if !adaptorRef.append(buffer, withPresentationTime: pts) {
                        appendFailureBox.message =
                            "append returned false at frame \(frame)"
                        counter.markDone()
                        inputRef.markAsFinished()
                        if counter.tryClaimResume() { continuation.resume() }
                        return
                    }
                    counter.increment()
                }
            }
        }

        await writer.finishWriting()
        if let appendErr = appendFailureBox.message {
            // Surface writer.error if it has a richer message, else our marker.
            let msg = writer.error?.localizedDescription ?? appendErr
            try? FileManager.default.removeItem(at: outURL)
            throw BakeError.appendFailed(msg)
        }
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: outURL)
            throw BakeError.writerFinishFailed(
                writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)"
            )
        }

        return outURL
    }

    // MARK: - Concurrency primitives for the pump

    private final class FrameCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _frame = 0
        private var _resumed = false
        private var _done = false

        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return _frame
        }

        func increment() {
            lock.lock(); defer { lock.unlock() }
            _frame += 1
        }

        /// Returns true exactly once. The caller is expected to call
        /// `continuation.resume()` only when this returns true.
        func tryClaimResume() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if _resumed { return false }
            _resumed = true
            return true
        }

        /// Read-only check used at the top of each pump-block invocation
        /// to short-circuit RE-ENTRY after `markAsFinished`. Reading does
        /// NOT set `_done` — that's only set explicitly via `markDone()`
        /// when a finish path is actually taken.
        var isDone: Bool {
            lock.lock(); defer { lock.unlock() }
            return _done
        }

        /// Mark the bake as done. Call this once when transitioning into
        /// a finish path (frame budget reached or append failed).
        func markDone() {
            lock.lock(); defer { lock.unlock() }
            _done = true
        }
    }

    private final class AppendFailureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _message: String?

        var message: String? {
            get { lock.lock(); defer { lock.unlock() }; return _message }
            set { lock.lock(); defer { lock.unlock() }; _message = newValue }
        }
    }

    enum BakeError: Error, LocalizedError {
        case invalidDuration
        case unreadableSource(String)
        case decodeFailed(String)
        case writerSetupFailed(String)
        case writerFinishFailed(String)
        case appendFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidDuration: return "Still duration must be > 0."
            case .unreadableSource(let n): return "Could not read \(n)."
            case .decodeFailed(let n): return "Could not decode \(n)."
            case .writerSetupFailed(let m): return "Could not set up bake writer: \(m)"
            case .writerFinishFailed(let m): return "Bake failed to finalize: \(m)"
            case .appendFailed(let m): return "Could not write still frame: \(m)"
            }
        }
    }
}
