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
    case textMarkerRange(AccessibilityTextMarkerRange)
    case point(CGPoint)
    case size(CGSize)
    case rect(CGRect)
}

struct AccessibilityTextMarkerRange: Equatable, Hashable, Sendable {
    let startMarker: Data
    let endMarker: Data

    var isNonEmpty: Bool {
        !startMarker.isEmpty && !endMarker.isEmpty && startMarker != endMarker
    }

    init(_ range: AXTextMarkerRange) {
        startMarker = Self.markerData(AXTextMarkerRangeCopyStartMarker(range))
        endMarker = Self.markerData(AXTextMarkerRangeCopyEndMarker(range))
    }

    init(startMarker: Data, endMarker: Data) {
        self.startMarker = startMarker
        self.endMarker = endMarker
    }

    func makeAXTextMarkerRange() -> AXTextMarkerRange {
        let startBytes = [UInt8](startMarker)
        let endBytes = [UInt8](endMarker)
        return AXTextMarkerRangeCreateWithBytes(
            kCFAllocatorDefault,
            startBytes,
            startMarker.count,
            endBytes,
            endMarker.count
        )
    }

    private static func markerData(_ marker: AXTextMarker) -> Data {
        let bytes = AXTextMarkerGetBytePtr(marker)
        let length = AXTextMarkerGetLength(marker)
        guard length > 0 else { return Data() }
        return Data(bytes: bytes, count: length)
    }
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
    func makeApplicationElement(processIdentifier: pid_t) throws -> AccessibilityElementID
    func makeSystemWideElement() throws -> AccessibilityElementID
    func setMessagingTimeout(_ timeout: TimeInterval, for element: AccessibilityElementID) throws
    func copyAttribute(_ attribute: String, from element: AccessibilityElementID) throws -> AccessibilityValue
    func copyParameterizedAttribute(
        _ attribute: String,
        parameter: AccessibilityValue,
        from element: AccessibilityElementID
    ) throws -> AccessibilityValue
}

protocol AccessibilityElementWriting: Sendable {
    func isAttributeSettable(_ attribute: String, for element: AccessibilityElementID) throws -> Bool
    func setAttribute(_ attribute: String, value: AccessibilityValue, for element: AccessibilityElementID) throws
}

final class MacOSAccessibilityElementAdapter: AccessibilityElementReading, AccessibilityElementWriting, @unchecked Sendable {
    func makeApplicationElement(processIdentifier: pid_t) throws -> AccessibilityElementID {
        AccessibilityElementID(nativeElement: AXUIElementCreateApplication(processIdentifier))
    }

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
        do {
            return try decode(rawValue)
        } catch {
            SafeLogger.selectionValueDecodeFailed(attribute: attribute, typeIdentifier: CFGetTypeID(rawValue))
            throw error
        }
    }

    func copyParameterizedAttribute(
        _ attribute: String,
        parameter: AccessibilityValue,
        from element: AccessibilityElementID
    ) throws -> AccessibilityValue {
        let nativeElement = try requireNativeElement(element)
        let parameterValue: CFTypeRef
        switch parameter {
        case let .range(range):
            var cfRange = CFRange(location: range.location, length: range.length)
            guard let value = AXValueCreate(.cfRange, &cfRange) else {
                throw AccessibilityAdapterError.invalidValue
            }
            parameterValue = value
        case let .textMarkerRange(range):
            parameterValue = range.makeAXTextMarkerRange()
        default:
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
        do {
            return try decode(rawValue)
        } catch {
            SafeLogger.selectionValueDecodeFailed(attribute: attribute, typeIdentifier: CFGetTypeID(rawValue))
            throw error
        }
    }

    func isAttributeSettable(_ attribute: String, for element: AccessibilityElementID) throws -> Bool {
        let nativeElement = try requireNativeElement(element)
        var settable: DarwinBoolean = false
        try check(AXUIElementIsAttributeSettable(nativeElement, attribute as CFString, &settable))
        return settable.boolValue
    }

    func setAttribute(_ attribute: String, value: AccessibilityValue, for element: AccessibilityElementID) throws {
        let nativeElement = try requireNativeElement(element)
        let rawValue: CFTypeRef
        switch value {
        case let .string(string): rawValue = string as CFString
        case let .range(range):
            var cfRange = CFRange(location: range.location, length: range.length)
            guard let axValue = AXValueCreate(.cfRange, &cfRange) else {
                throw AccessibilityAdapterError.invalidValue
            }
            rawValue = axValue
        default:
            throw AccessibilityAdapterError.invalidValue
        }
        try check(AXUIElementSetAttributeValue(nativeElement, attribute as CFString, rawValue))
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
        try AccessibilityValueDecoder.decode(value, decodeAXValue: decodeAXValue)
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

enum AccessibilityValueDecoder {
    static func decode(
        _ value: CFTypeRef,
        decodeAXValue: (AXValue) throws -> AccessibilityValue
    ) throws -> AccessibilityValue {
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return .element(AccessibilityElementID(nativeElement: value as! AXUIElement))
        }
        if CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() {
            return .textMarkerRange(AccessibilityTextMarkerRange(value as! AXTextMarkerRange))
        }
        if let string = value as? String {
            return .string(string)
        }
        if CFGetTypeID(value) == CFAttributedStringGetTypeID() {
            let attributed = value as! CFAttributedString
            return .string(CFAttributedStringGetString(attributed) as String)
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            throw AccessibilityAdapterError.invalidValue
        }
        return try decodeAXValue(value as! AXValue)
    }
}
