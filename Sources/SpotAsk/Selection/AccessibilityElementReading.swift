import ApplicationServices
import CoreFoundation
import Foundation

struct AccessibilityElementID: Hashable, @unchecked Sendable {
    let rawValue: UInt64
    fileprivate let nativeElement: AXUIElement?

    init(rawValue: UInt64) {
        self.rawValue = rawValue
        nativeElement = nil
    }

    fileprivate init(nativeElement: AXUIElement) {
        rawValue = UInt64(CFHash(nativeElement))
        self.nativeElement = nativeElement
    }

    static func == (lhs: AccessibilityElementID, rhs: AccessibilityElementID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

enum AccessibilityValue: Equatable, Hashable, Sendable {
    case string(String)
    case element(AccessibilityElementID)
    case range(SelectionCharacterRange)
    case point(CGPoint)
    case size(CGSize)
    case rect(CGRect)
}

struct AccessibilityAXError: Equatable, Sendable {
    let rawValue: Int32

    static let failure = Self(rawValue: -25200)
    static let illegalArgument = Self(rawValue: -25201)
    static let invalidUIElement = Self(rawValue: -25202)
    static let invalidUIElementObserver = Self(rawValue: -25203)
    static let cannotComplete = Self(rawValue: -25204)
    static let attributeUnsupported = Self(rawValue: -25205)
    static let actionUnsupported = Self(rawValue: -25206)
    static let notificationUnsupported = Self(rawValue: -25207)
    static let notImplemented = Self(rawValue: -25208)
    static let notificationAlreadyRegistered = Self(rawValue: -25209)
    static let notificationNotRegistered = Self(rawValue: -25210)
    static let apiDisabled = Self(rawValue: -25211)
    static let noValue = Self(rawValue: -25212)
    static let parameterizedAttributeUnsupported = Self(rawValue: -25213)
    static let notEnoughPrecision = Self(rawValue: -25214)

    init(rawValue: Int32) {
        self.rawValue = rawValue
    }
}

enum AccessibilityAdapterError: Error, Equatable, Sendable {
    case ax(AccessibilityAXError)
    case invalidValue
}

protocol AccessibilityElementReading: Sendable {
    func makeSystemWideElement() throws -> AccessibilityElementID
    func setMessagingTimeout(_ timeout: TimeInterval, for element: AccessibilityElementID) throws
    func copyAttribute(_ attribute: String, from element: AccessibilityElementID) throws -> AccessibilityValue
    func copyParameterizedAttribute(
        _ attribute: String,
        parameter: AccessibilityValue,
        from element: AccessibilityElementID
    ) throws -> AccessibilityValue
}

final class MacOSAccessibilityElementAdapter: AccessibilityElementReading, @unchecked Sendable {
    func makeSystemWideElement() throws -> AccessibilityElementID {
        AccessibilityElementID(nativeElement: AXUIElementCreateSystemWide())
    }

    func setMessagingTimeout(_ timeout: TimeInterval, for element: AccessibilityElementID) throws {
        let nativeElement = try requireNativeElement(element)
        try check(AXUIElementSetMessagingTimeout(nativeElement, Float(timeout)))
    }

    func copyAttribute(_ attribute: String, from element: AccessibilityElementID) throws -> AccessibilityValue {
        let nativeElement = try requireNativeElement(element)
        var rawValue: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(nativeElement, attribute as CFString, &rawValue))
        guard let rawValue else {
            throw AccessibilityAdapterError.invalidValue
        }
        return try decode(rawValue)
    }

    func copyParameterizedAttribute(
        _ attribute: String,
        parameter: AccessibilityValue,
        from element: AccessibilityElementID
    ) throws -> AccessibilityValue {
        let nativeElement = try requireNativeElement(element)
        guard case let .range(range) = parameter else {
            throw AccessibilityAdapterError.invalidValue
        }

        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameterValue = AXValueCreate(.cfRange, &cfRange) else {
            throw AccessibilityAdapterError.invalidValue
        }

        var rawValue: CFTypeRef?
        try check(
            AXUIElementCopyParameterizedAttributeValue(
                nativeElement,
                attribute as CFString,
                parameterValue,
                &rawValue
            )
        )
        guard let rawValue else {
            throw AccessibilityAdapterError.invalidValue
        }
        return try decode(rawValue)
    }

    private func requireNativeElement(_ element: AccessibilityElementID) throws -> AXUIElement {
        guard let nativeElement = element.nativeElement else {
            throw AccessibilityAdapterError.invalidValue
        }
        return nativeElement
    }

    private func check(_ error: AXError) throws {
        guard error == .success else {
            throw AccessibilityAdapterError.ax(AccessibilityAXError(rawValue: error.rawValue))
        }
    }

    private func decode(_ value: CFTypeRef) throws -> AccessibilityValue {
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return .element(AccessibilityElementID(nativeElement: value as! AXUIElement))
        }
        if let string = value as? String {
            return .string(string)
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            throw AccessibilityAdapterError.invalidValue
        }
        return try decodeAXValue(value as! AXValue)
    }

    private func decodeAXValue(_ value: AXValue) throws -> AccessibilityValue {
        switch AXValueGetType(value) {
        case .cfRange:
            var range = CFRange()
            guard AXValueGetValue(value, .cfRange, &range) else {
                throw AccessibilityAdapterError.invalidValue
            }
            return .range(SelectionCharacterRange(location: range.location, length: range.length))
        case .cgPoint:
            var point = CGPoint.zero
            guard AXValueGetValue(value, .cgPoint, &point) else {
                throw AccessibilityAdapterError.invalidValue
            }
            return .point(point)
        case .cgSize:
            var size = CGSize.zero
            guard AXValueGetValue(value, .cgSize, &size) else {
                throw AccessibilityAdapterError.invalidValue
            }
            return .size(size)
        case .cgRect:
            var rect = CGRect.zero
            guard AXValueGetValue(value, .cgRect, &rect) else {
                throw AccessibilityAdapterError.invalidValue
            }
            return .rect(rect)
        default:
            throw AccessibilityAdapterError.invalidValue
        }
    }
}
