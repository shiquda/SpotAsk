import CoreGraphics
import Foundation

/// What the attachment payload really contains. Documents, PDF text extractions
/// and code files all normalize to text; only images keep binary data.
enum AttachmentKind: String, Codable, Equatable, Sendable {
    case image
    case text
    case code
}

struct ChatAttachment: Identifiable, Codable, Equatable, Sendable {
    enum Payload: Codable, Equatable, Sendable {
        case image(data: Data)
        case text(text: String, originalKind: AttachmentKind)

        private enum CodingKeys: String, CodingKey {
            case kind
            case imageData
            case text
            case originalKind
        }

        private enum PayloadKind: String, Codable {
            case image
            case text
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(PayloadKind.self, forKey: .kind) {
            case .image:
                self = .image(data: try container.decode(Data.self, forKey: .imageData))
            case .text:
                self = .text(
                    text: try container.decode(String.self, forKey: .text),
                    originalKind: try container.decode(AttachmentKind.self, forKey: .originalKind)
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .image(data):
                try container.encode(PayloadKind.image, forKey: .kind)
                try container.encode(data, forKey: .imageData)
            case let .text(text, originalKind):
                try container.encode(PayloadKind.text, forKey: .kind)
                try container.encode(text, forKey: .text)
                try container.encode(originalKind, forKey: .originalKind)
            }
        }
    }

    let id: UUID
    let filename: String
    let mimeType: String
    let byteCount: Int
    let payload: Payload
    /// True when the extracted text was cut off at the per-attachment limit.
    var isTruncated: Bool

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        byteCount: Int,
        payload: Payload,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.payload = payload
        self.isTruncated = isTruncated
    }

    var kind: AttachmentKind {
        switch payload {
        case .image: .image
        case let .text(_, originalKind): originalKind
        }
    }
}

/// Central home for attachment limits so no magic numbers leak into the
/// processor, the view model, or the composer. Deliberately light for v0.2.
enum AttachmentLimits {
    static let maxAttachmentsPerMessage = 8
    static let maxImageFileBytes = 10 * 1024 * 1024
    static let maxNormalizedImageBytes = 5 * 1024 * 1024
    static let maxImageDimension: CGFloat = 4096
    static let maxTextFileBytes = 5 * 1024 * 1024
    static let maxExtractedTextPerAttachment = 60_000
}

enum AttachmentError: LocalizedError, Equatable, Sendable {
    case directoryNotAllowed
    case fileTooLarge
    case unsupportedFileType(String)
    case imageDecodingFailed
    case textDecodingFailed
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .directoryNotAllowed:
            L10n.string("chat.attachmentDirectoryNotAllowed")
        case .fileTooLarge:
            L10n.string("chat.attachmentTooLarge")
        case let .unsupportedFileType(filename):
            L10n.string("chat.attachmentUnsupported", filename)
        case .imageDecodingFailed:
            L10n.string("chat.attachmentImageDecodeFailed")
        case .textDecodingFailed:
            L10n.string("chat.attachmentTextDecodeFailed")
        case .fileReadFailed:
            L10n.string("chat.attachmentFileReadFailed")
        }
    }
}
