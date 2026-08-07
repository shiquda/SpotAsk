import AppKit
import UniformTypeIdentifiers

/// Ingests files, clipboard data and screenshots, normalizes them, and returns
/// ready-to-send `ChatAttachment` values. Runs off the main actor so disk
/// reads, image resizing and encoding never block the composer.
actor AttachmentProcessor {
    static let shared = AttachmentProcessor()

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "heif", "tiff", "gif"
    ]
    private static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "java",
        "c", "h", "cpp", "hpp", "sh"
    ]
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "yaml", "yml", "xml", "csv", "tsv", "log"
    ]

    func process(url inputURL: URL) async throws -> ChatAttachment {
        let url = inputURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { throw AttachmentError.fileReadFailed }
        if isDirectory.boolValue { throw AttachmentError.directoryNotAllowed }
        guard let kind = Self.kind(for: url) else {
            throw AttachmentError.unsupportedFileType(url.lastPathComponent)
        }
        switch kind {
        case .image:
            return try processImage(url: url)
        case .text, .code:
            return try processText(url: url, kind: kind)
        }
    }

    /// Normalizes clipboard screenshot data (usually PNG or TIFF) to PNG so the
    /// provider receives a stable, compact image.
    func processScreenshot(_ imageData: Data) async throws -> ChatAttachment {
        let (data, mimeType) = try normalizedImage(from: imageData)
        return ChatAttachment(
            filename: "screenshot.png",
            mimeType: mimeType,
            byteCount: data.count,
            payload: .image(data: data)
        )
    }

    private func processImage(url: URL) throws -> ChatAttachment {
        let data = try Self.readData(url: url)
        guard data.count <= AttachmentLimits.maxImageFileBytes else {
            throw AttachmentError.fileTooLarge
        }
        let (outputData, mimeType) = try normalizedImage(from: data)
        return ChatAttachment(
            filename: url.lastPathComponent,
            mimeType: mimeType,
            byteCount: outputData.count,
            payload: .image(data: outputData)
        )
    }

    private func processText(url: URL, kind: AttachmentKind) throws -> ChatAttachment {
        let data = try Self.readData(url: url)
        guard data.count <= AttachmentLimits.maxTextFileBytes else {
            throw AttachmentError.fileTooLarge
        }
        guard var text = String(data: data, encoding: .utf8) else {
            throw AttachmentError.textDecodingFailed
        }
        var isTruncated = false
        if text.count > AttachmentLimits.maxExtractedTextPerAttachment {
            text = String(text.prefix(AttachmentLimits.maxExtractedTextPerAttachment))
            isTruncated = true
        }
        return ChatAttachment(
            filename: url.lastPathComponent,
            mimeType: "text/plain",
            byteCount: text.utf8.count,
            payload: .text(text: text, originalKind: kind),
            isTruncated: isTruncated
        )
    }

    private static func readData(url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw AttachmentError.fileReadFailed
        }
    }

    /// Decodes any supported image (PNG/JPEG/WebP/HEIC), downscales the longest
    /// side to 4096px, and re-encodes as PNG (alpha) or JPEG (quality 0.85).
    private func normalizedImage(from data: Data) throws -> (data: Data, mimeType: String) {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AttachmentError.imageDecodingFailed
        }
        let maxSide = AttachmentLimits.maxImageDimension
        let originalSize = image.size
        var outputSize = originalSize
        if max(originalSize.width, originalSize.height) > maxSide {
            let scale = maxSide / max(originalSize.width, originalSize.height)
            outputSize = NSSize(
                width: (originalSize.width * scale).rounded(),
                height: (originalSize.height * scale).rounded()
            )
        }

        let outputRep: NSBitmapImageRep
        if outputSize != originalSize {
            guard let resized = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(outputSize.width),
                pixelsHigh: Int(outputSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { throw AttachmentError.imageDecodingFailed }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
            image.draw(in: NSRect(origin: .zero, size: outputSize))
            NSGraphicsContext.restoreGraphicsState()
            outputRep = resized
        } else {
            outputRep = NSBitmapImageRep(cgImage: cgImage)
        }

        let hasAlpha = outputRep.hasAlpha
        let encoding: NSBitmapImageRep.FileType = hasAlpha ? .png : .jpeg
        let properties: [NSBitmapImageRep.PropertyKey: Any] = hasAlpha
            ? [:]
            : [.compressionFactor: 0.85]
        guard let outputData = outputRep.representation(using: encoding, properties: properties) else {
            throw AttachmentError.imageDecodingFailed
        }
        guard outputData.count <= AttachmentLimits.maxNormalizedImageBytes else {
            throw AttachmentError.fileTooLarge
        }
        return (outputData, hasAlpha ? "image/png" : "image/jpeg")
    }

    private static func kind(for url: URL) -> AttachmentKind? {
        let ext = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(ext) { return .image }
        if Self.codeExtensions.contains(ext) { return .code }
        if Self.textExtensions.contains(ext) { return .text }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .sourceCode) { return .code }
            if type.conforms(to: .text) { return .text }
        }
        return nil
    }
}
