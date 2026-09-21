import CoreGraphics
import Foundation

enum SelectionDiagnosticsFormatting {
    static func point(_ point: CGPoint) -> String {
        String(format: "(%.1f,%.1f)", point.x, point.y)
    }

    static func rect(_ rect: CGRect) -> String {
        String(format: "(%.1f,%.1f,%.1f,%.1f)", rect.minX, rect.minY, rect.width, rect.height)
    }

    static func size(_ size: CGSize) -> String {
        String(format: "(%.1f,%.1f)", size.width, size.height)
    }

    static func error(_ error: Error) -> String {
        if let adapterError = error as? AccessibilityAdapterError {
            switch adapterError {
            case let .ax(axError): return "ax(\(axError.rawValue))"
            case .invalidValue: return "invalidValue"
            }
        }
        return String(describing: error)
    }

    static func anchor(_ anchor: SelectionAnchor) -> String {
        switch anchor {
        case let .selectionRect(rect): "selection=\(Self.rect(rect))"
        case let .elementRect(rect): "element=\(Self.rect(rect))"
        case let .pointer(point): "pointer=\(Self.point(point))"
        }
    }
}
