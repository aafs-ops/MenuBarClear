// IconStream.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// A live, recoloured copy of the status items (the icons on the right side of
// the menu bar). Used only when macOS tints those icons the wrong way for the
// wallpaper (e.g. white icons over a bright wallpaper): MenuBarClear then sits
// in front of the real icons and shows this copy instead. Monochrome glyph
// pixels are recoloured black/white; coloured pixels (battery, mic dot…) are kept.

import AppKit
import CoreMedia
import ScreenCaptureKit

final class IconStream: NSObject, SCStreamOutput, SCStreamDelegate {
    var onImage: ((CGImage) -> Void)?
    var isRunning: Bool { stream != nil }

    var darkTarget: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _darkTarget }
        set { lock.lock(); _darkTarget = newValue; lock.unlock() }
    }

    private var stream: SCStream?
    private var windowIDs: [CGWindowID] = []
    private let queue = DispatchQueue(label: "io.github.aafs-ops.MenuBarClear.icons", qos: .userInteractive)
    private let lock = NSLock()
    private var _darkTarget = true

    /// Starts the stream, or updates which status-item windows it shows.
    /// `excluding` must contain MenuBarClear's own overlay window.
    func update(displayID: CGDirectDisplayID, bar: CGRect, statusLayer: Int, scale: CGFloat,
                excluding: Set<CGWindowID>) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
        let windows = content.windows.filter {
            $0.windowLayer == statusLayer && $0.frame.width > 0 && $0.frame.intersects(bar)
                && !excluding.contains($0.windowID)
        }
        let ids = windows.map(\.windowID).sorted()
        if ids == windowIDs, stream != nil { return }
        windowIDs = ids

        let filter = SCContentFilter(display: display, including: windows)
        if let stream {
            try? await stream.updateContentFilter(filter)
            return
        }

        let displayBounds = CGDisplayBounds(displayID)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: bar.minX - displayBounds.minX, y: bar.minY - displayBounds.minY,
                                   width: bar.width, height: bar.height)
        config.width = Int(bar.width * scale)
        config.height = Int(bar.height * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.backgroundColor = CGColor.clear
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await newStream.startCapture()
            stream = newStream
        } catch {
            windowIDs = []
        }
    }

    func stop() {
        let old = stream
        stream = nil
        windowIDs = []
        Task { try? await old?.stopCapture() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.stream = nil; self.windowIDs = [] }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue),
              let dstBase = ctx.data else { return }

        let dark = darkTarget
        let src = base.assumingMemoryBound(to: UInt8.self)
        let dst = dstBase.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let s = src + y * srcBytesPerRow
            let d = dst + y * width * 4
            for x in 0..<width {
                let o = x * 4
                let b = Int(s[o]), g = Int(s[o + 1]), r = Int(s[o + 2]), a = Int(s[o + 3])
                if a == 0 {
                    d[o] = 0; d[o + 1] = 0; d[o + 2] = 0; d[o + 3] = 0
                    continue
                }
                let spread = max(r, g, b) - min(r, g, b)
                if spread * 255 < 60 * a {                      // monochrome → recolour
                    let v = UInt8(dark ? 0 : a)                 // premultiplied black / white
                    d[o] = v; d[o + 1] = v; d[o + 2] = v
                } else {                                        // coloured → keep
                    d[o] = UInt8(b); d[o + 1] = UInt8(g); d[o + 2] = UInt8(r)
                }
                d[o + 3] = UInt8(a)
            }
        }
        guard let image = ctx.makeImage() else { return }
        DispatchQueue.main.async { self.onImage?(image) }
    }
}
