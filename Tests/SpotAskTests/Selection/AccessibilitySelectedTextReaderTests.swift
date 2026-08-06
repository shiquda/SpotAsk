import AppKit
import Foundation
import Testing
@testable import SpotAsk

@Suite("Accessibility selected text reader")
struct AccessibilitySelectedTextReaderTests {
    @Test("Permission denial does not access Accessibility elements")
    func permissionDenialStopsBeforeAccessibilityAccess() async {
        let fixture = ReaderFixture(isTrusted: false)
        let reader = fixture.makeReader()

        await #expect(throws: SelectionReadingError.permissionDenied) {
            try await reader.readSelection(promptForPermission: true)
        }
        #expect(fixture.elementReader.calls.isEmpty)
        #expect(fixture.permissionChecker.promptRequests == [true])
    }

    @Test("Focused elements can provide a selected-text snapshot")
    func focusedElementSelection() async throws {
        let fixture = ReaderFixture()
        fixture.configureFocusedSelection(text: "Line one\nLine two", range: .init(location: 5, length: 8))
        fixture.elementReader.set(
            .rect(CGRect(x: 100, y: 200, width: 120, height: 24)),
            attribute: fixture.boundsAttribute,
            element: fixture.focusedElement,
            parameter: .range(.init(location: 5, length: 8))
        )
        let reader = fixture.makeReader()

        let snapshot = try await reader.readSelection(promptForPermission: false)

        #expect(snapshot.text == "Line one\nLine two")
        #expect(snapshot.source == fixture.source)
        #expect(snapshot.selectedRange == .init(location: 5, length: 8))
        #expect(snapshot.anchor == .pointer(CGPoint(x: 30, y: 40)))
        #expect(fixture.elementReader.calls.contains(.setMessagingTimeout(fixture.applicationElement)))
        #expect(!fixture.elementReader.calls.contains(.setMessagingTimeout(fixture.focusedElement)))
    }

    @Test("The reader searches a bounded parent chain")
    func parentChainIsBoundedAtSixElements() async {
        let fixture = ReaderFixture()
        let elements = (1 ... 7).map { AccessibilityElementID(rawValue: UInt64($0)) }
        fixture.setFocusedElement(elements[0])
        for index in 0 ..< elements.count - 1 {
            fixture.elementReader.set(.element(elements[index + 1]), attribute: fixture.parentAttribute, element: elements[index])
        }
        fixture.elementReader.set(.string("Selected only beyond the limit"), attribute: fixture.selectedTextAttribute, element: elements[6])
        let reader = fixture.makeReader()

        await #expect(throws: SelectionReadingError.noSelection) {
            try await reader.readSelection(promptForPermission: false)
        }
        #expect(!fixture.elementReader.calls.contains(.attribute(fixture.selectedTextAttribute, elements[6])))
        #expect(!fixture.elementReader.calls.contains(.attribute(fixture.roleAttribute, elements[6])))
    }

    @Test("A parent selection is used when the focused control has no selected-text attribute")
    func parentFallbackSelection() async throws {
        let fixture = ReaderFixture()
        let parent = AccessibilityElementID(rawValue: 2)
        fixture.setFocusedElement(fixture.focusedElement)
        fixture.elementReader.set(.element(parent), attribute: fixture.parentAttribute, element: fixture.focusedElement)
        fixture.elementReader.set(.string("Parent selection"), attribute: fixture.selectedTextAttribute, element: parent)
        fixture.elementReader.set(.range(.init(location: 0, length: 16)), attribute: fixture.selectedRangeAttribute, element: parent)
        fixture.elementReader.set(.point(CGPoint(x: 10, y: 10)), attribute: fixture.positionAttribute, element: parent)
        fixture.elementReader.set(.size(CGSize(width: 200, height: 40)), attribute: fixture.sizeAttribute, element: parent)
        let reader = fixture.makeReader()

        let snapshot = try await reader.readSelection(promptForPermission: false)

        #expect(snapshot.text == "Parent selection")
        #expect(snapshot.selectedRange == .init(location: 0, length: 16))
        #expect(snapshot.anchor == .pointer(CGPoint(x: 30, y: 40)))
    }

    @Test("A secure ancestor stops all selected text reads")
    func secureAncestorPreflightStopsBeforeTextAccess() async {
        let fixture = ReaderFixture()
        let parent = AccessibilityElementID(rawValue: 2)
        fixture.setFocusedElement(fixture.focusedElement)
        fixture.elementReader.set(.element(parent), attribute: fixture.parentAttribute, element: fixture.focusedElement)
        fixture.elementReader.set(.string("AXSecureTextField"), attribute: fixture.subroleAttribute, element: parent)
        fixture.elementReader.set(.string("must never be read"), attribute: fixture.selectedTextAttribute, element: fixture.focusedElement)
        let reader = fixture.makeReader()

        await #expect(throws: SelectionReadingError.sensitiveField) {
            try await reader.readSelection(promptForPermission: false)
        }
        #expect(!fixture.elementReader.calls.contains { call in
            if case let .attribute(attribute, _) = call {
                return attribute == fixture.selectedTextAttribute || attribute == fixture.selectedRangeAttribute
            }
            return false
        })
        #expect(!fixture.elementReader.calls.contains { call in
            if case let .parameterized(attribute, _, _) = call {
                return attribute == fixture.boundsAttribute
            }
            return false
        })
    }

    @Test("A zero-length selected range skips range bounds and uses the element frame")
    func zeroLengthRangeFallsBackToElementFrame() async throws {
        let fixture = ReaderFixture()
        fixture.configureFocusedSelection(text: "Text", range: .init(location: 2, length: 0))
        fixture.elementReader.set(.point(CGPoint(x: -400, y: 40)), attribute: fixture.positionAttribute, element: fixture.focusedElement)
        fixture.elementReader.set(.size(CGSize(width: 120, height: 60)), attribute: fixture.sizeAttribute, element: fixture.focusedElement)
        let reader = fixture.makeReader()

        let snapshot = try await reader.readSelection(promptForPermission: false)

        #expect(snapshot.selectedRange == nil)
        #expect(snapshot.anchor == .pointer(CGPoint(x: 30, y: 40)))
        #expect(!fixture.elementReader.calls.contains { call in
            if case let .parameterized(attribute, _, _) = call {
                return attribute == fixture.boundsAttribute
            }
            return false
        })
    }

    @Test("Bounds failures fall back through element frame to the pointer")
    func boundsAndFrameFallbacks() async throws {
        let elementFrameFixture = ReaderFixture()
        elementFrameFixture.configureFocusedSelection(text: "Text", range: .init(location: 0, length: 4))
        elementFrameFixture.elementReader.setError(
            .ax(.cannotComplete),
            parameterizedAttribute: elementFrameFixture.boundsAttribute,
            element: elementFrameFixture.focusedElement,
            parameter: .range(.init(location: 0, length: 4))
        )
        elementFrameFixture.elementReader.set(.point(CGPoint(x: 20, y: 30)), attribute: elementFrameFixture.positionAttribute, element: elementFrameFixture.focusedElement)
        elementFrameFixture.elementReader.set(.size(CGSize(width: 80, height: 50)), attribute: elementFrameFixture.sizeAttribute, element: elementFrameFixture.focusedElement)

        let elementFrameSnapshot = try await elementFrameFixture.makeReader().readSelection(promptForPermission: false)
        #expect(elementFrameSnapshot.anchor == .pointer(CGPoint(x: 30, y: 40)))

        let pointerFixture = ReaderFixture(pointer: CGPoint(x: -55, y: 310))
        pointerFixture.configureFocusedSelection(text: "Text", range: .init(location: 0, length: 4))
        let pointerSnapshot = try await pointerFixture.makeReader().readSelection(promptForPermission: false)
        #expect(pointerSnapshot.anchor == .pointer(CGPoint(x: -55, y: 310)))
    }


    @Test(arguments: [
        (AccessibilityAXError.cannotComplete, SelectionReadingError.applicationUnresponsive),
        (AccessibilityAXError.notImplemented, SelectionReadingError.unsupportedApplication),
        (AccessibilityAXError.apiDisabled, SelectionReadingError.accessibilityDisabled),
        (AccessibilityAXError.invalidUIElement, SelectionReadingError.applicationUnavailable)
    ])
    func mapsAccessibilityFailures(error: AccessibilityAXError, expected: SelectionReadingError) async {
        let fixture = ReaderFixture()
        fixture.setFocusedElement(fixture.focusedElement)
        fixture.elementReader.setError(.ax(error), attribute: fixture.selectedTextAttribute, element: fixture.focusedElement)
        let reader = fixture.makeReader()

        await #expect(throws: expected) {
            try await reader.readSelection(promptForPermission: false)
        }
    }

    @Test("Concurrent reads are serialized on the main execution context")
    func concurrentReadsUseOneAccessibilityExecutionContext() async throws {
        let fixture = ReaderFixture()
        fixture.configureFocusedSelection(text: "Text", range: .init(location: 0, length: 4))
        fixture.elementReader.copyDelay = 0.015
        let reader = fixture.makeReader()

        async let first = reader.readSelection(promptForPermission: false)
        async let second = reader.readSelection(promptForPermission: false)
        _ = try await (first, second)

        #expect(fixture.elementReader.maximumConcurrentCopies == 1)
    }
}

@Suite("Selection anchor coordinate conversion")
struct SelectionAnchorCoordinateConverterTests {
    @Test("Conversion keeps the matching display origin and converts vertical coordinates")
    func usesMatchingDisplayWithNegativeCoordinates() {
        let main = SelectionScreenCoordinateSpace(
            displayBounds: CGRect(x: 0, y: 0, width: 2_000, height: 1_200),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_000, height: 600),
            scaleFactor: 2
        )
        let leftDisplay = SelectionScreenCoordinateSpace(
            displayBounds: CGRect(x: -1_280, y: 200, width: 1_280, height: 1_024),
            appKitFrame: CGRect(x: -1_280, y: -424, width: 1_280, height: 1_024),
            scaleFactor: 1
        )
        let rect = CGRect(x: -1_180, y: 300, width: 160, height: 40)

        let converted = SelectionAnchorCoordinateConverter.appKitRect(
            fromAccessibilityRect: rect,
            coordinateSpaces: [main, leftDisplay]
        )

        #expect(converted == CGRect(x: -1_180, y: 460, width: 160, height: 40))
    }

    @Test("Missing display bounds leaves the reader to use a lower-priority anchor")
    func missingDisplayReturnsNil() {
        #expect(
            SelectionAnchorCoordinateConverter.appKitRect(
                fromAccessibilityRect: CGRect(x: 5_000, y: 5_000, width: 10, height: 10),
                coordinateSpaces: []
            ) == nil
        )
    }

    @Test("Retina display bounds are already expressed in points")
    func retinaCoordinatesAreNotScaledTwice() {
        let main = SelectionScreenCoordinateSpace(
            displayBounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            scaleFactor: 2
        )

        let converted = SelectionAnchorCoordinateConverter.appKitRect(
            fromAccessibilityRect: CGRect(x: 100, y: 700, width: 120, height: 24),
            coordinateSpaces: [main]
        )

        #expect(converted == CGRect(x: 100, y: 258, width: 120, height: 24))
    }

    @Test("Conversion does not depend on pointer location")
    func conversionDoesNotRequirePointerLocation() {
        let main = SelectionScreenCoordinateSpace(
            displayBounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            scaleFactor: 2
        )

        let converted = SelectionAnchorCoordinateConverter.appKitRect(
            fromAccessibilityRect: CGRect(x: 100, y: 700, width: 120, height: 24),
            coordinateSpaces: [main]
        )

        #expect(converted == CGRect(x: 100, y: 258, width: 120, height: 24))
    }
}

private final class ReaderFixture: @unchecked Sendable {
    let applicationElement = AccessibilityElementID(rawValue: 100)
    let focusedElement = AccessibilityElementID(rawValue: 1)
    let source = SelectionSourceApplication(
        processIdentifier: 42,
        bundleIdentifier: "com.example.Editor",
        localizedName: "Editor"
    )
    let elementReader = FakeAccessibilityElementReader()
    let permissionChecker: FakePermissionChecker
    let applicationProvider: FakeApplicationProvider
    let pointerLocationProvider: FakePointerLocationProvider

    let focusedAttribute = kAXFocusedUIElementAttribute as String
    let parentAttribute = kAXParentAttribute as String
    let roleAttribute = kAXRoleAttribute as String
    let subroleAttribute = kAXSubroleAttribute as String
    let selectedTextAttribute = kAXSelectedTextAttribute as String
    let selectedRangeAttribute = kAXSelectedTextRangeAttribute as String
    let boundsAttribute = kAXBoundsForRangeParameterizedAttribute as String
    let positionAttribute = kAXPositionAttribute as String
    let sizeAttribute = kAXSizeAttribute as String

    init(isTrusted: Bool = true, pointer: CGPoint = CGPoint(x: 30, y: 40)) {
        permissionChecker = FakePermissionChecker(isTrusted: isTrusted)
        applicationProvider = FakeApplicationProvider(source: source, currentProcessIdentifier: 99)
        pointerLocationProvider = FakePointerLocationProvider(point: pointer)
        elementReader.applicationElement = applicationElement
    }

    func makeReader() -> AccessibilitySelectedTextReader {
        AccessibilitySelectedTextReader(
            permissionChecker: permissionChecker,
            applicationProvider: applicationProvider,
            elementReader: elementReader,
            pointerLocationProvider: pointerLocationProvider
        )
    }

    func setFocusedElement(_ element: AccessibilityElementID) {
        elementReader.set(.element(element), attribute: focusedAttribute, element: applicationElement)
    }

    func configureFocusedSelection(text: String, range: SelectionCharacterRange) {
        setFocusedElement(focusedElement)
        elementReader.set(.string(text), attribute: selectedTextAttribute, element: focusedElement)
        elementReader.set(.range(range), attribute: selectedRangeAttribute, element: focusedElement)
    }
}

private final class FakePermissionChecker: AccessibilityPermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let isTrustedValue: Bool
    private(set) var promptRequests: [Bool] = []

    init(isTrusted: Bool) {
        isTrustedValue = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        lock.lock()
        promptRequests.append(prompt)
        lock.unlock()
        return isTrustedValue
    }
}

private struct FakeApplicationProvider: ForegroundSelectionApplicationProviding {
    let source: SelectionSourceApplication?
    let currentProcessIdentifierValue: pid_t

    init(source: SelectionSourceApplication?, currentProcessIdentifier: pid_t) {
        self.source = source
        currentProcessIdentifierValue = currentProcessIdentifier
    }

    func frontmostApplication() -> SelectionSourceApplication? {
        source
    }

    func currentProcessIdentifier() -> pid_t {
        currentProcessIdentifierValue
    }
}

private struct FakePointerLocationProvider: PointerLocationProviding {
    let point: CGPoint

    func location() -> CGPoint {
        point
    }
}

private struct FakeScreenProvider: SelectionScreenProviding {
    let spaces: [SelectionScreenCoordinateSpace]

    func coordinateSpaces() -> [SelectionScreenCoordinateSpace] {
        spaces
    }
}

private final class FakeAccessibilityElementReader: AccessibilityElementReading, @unchecked Sendable {
    enum Call: Equatable {
        case makeApplicationElement(pid_t)
        case setMessagingTimeout(AccessibilityElementID)
        case attribute(String, AccessibilityElementID)
        case parameterized(String, AccessibilityValue, AccessibilityElementID)
    }

    private enum Response {
        case value(AccessibilityValue)
        case error(AccessibilityAdapterError)
    }

    private struct AttributeKey: Hashable {
        let attribute: String
        let element: AccessibilityElementID
    }

    private struct ParameterizedAttributeKey: Hashable {
        let attribute: String
        let parameter: AccessibilityValue
        let element: AccessibilityElementID
    }

    private let lock = NSLock()
    private var attributeResponses: [AttributeKey: Response] = [:]
    private var parameterizedAttributeResponses: [ParameterizedAttributeKey: Response] = [:]
    private var activeCopies = 0
    private(set) var maximumConcurrentCopies = 0
    private(set) var calls: [Call] = []
    var copyDelay: TimeInterval = 0
    var applicationElement = AccessibilityElementID(rawValue: 100)

    func set(_ value: AccessibilityValue, attribute: String, element: AccessibilityElementID) {
        lock.lock()
        attributeResponses[AttributeKey(attribute: attribute, element: element)] = .value(value)
        lock.unlock()
    }

    func setError(_ error: AccessibilityAdapterError, attribute: String, element: AccessibilityElementID) {
        lock.lock()
        attributeResponses[AttributeKey(attribute: attribute, element: element)] = .error(error)
        lock.unlock()
    }

    func set(
        _ value: AccessibilityValue,
        attribute: String,
        element: AccessibilityElementID,
        parameter: AccessibilityValue
    ) {
        lock.lock()
        parameterizedAttributeResponses[
            ParameterizedAttributeKey(attribute: attribute, parameter: parameter, element: element)
        ] = .value(value)
        lock.unlock()
    }

    func setError(
        _ error: AccessibilityAdapterError,
        parameterizedAttribute attribute: String,
        element: AccessibilityElementID,
        parameter: AccessibilityValue
    ) {
        lock.lock()
        parameterizedAttributeResponses[
            ParameterizedAttributeKey(attribute: attribute, parameter: parameter, element: element)
        ] = .error(error)
        lock.unlock()
    }

    func makeApplicationElement(processIdentifier: pid_t) throws -> AccessibilityElementID {
        lock.lock()
        calls.append(.makeApplicationElement(processIdentifier))
        let result = applicationElement
        lock.unlock()
        return result
    }

    func setMessagingTimeout(_: TimeInterval, for element: AccessibilityElementID) throws {
        lock.lock()
        calls.append(.setMessagingTimeout(element))
        lock.unlock()
    }

    func copyAttribute(_ attribute: String, from element: AccessibilityElementID) throws -> AccessibilityValue {
        let response = beginCopy(call: .attribute(attribute, element), response: attributeResponses[AttributeKey(attribute: attribute, element: element)])
        defer { endCopy() }
        return try resolve(response)
    }

    func copyParameterizedAttribute(
        _ attribute: String,
        parameter: AccessibilityValue,
        from element: AccessibilityElementID
    ) throws -> AccessibilityValue {
        let response = beginCopy(
            call: .parameterized(attribute, parameter, element),
            response: parameterizedAttributeResponses[
                ParameterizedAttributeKey(attribute: attribute, parameter: parameter, element: element)
            ]
        )
        defer { endCopy() }
        return try resolve(response)
    }

    private func beginCopy(call: Call, response: Response?) -> Response? {
        lock.lock()
        calls.append(call)
        activeCopies += 1
        maximumConcurrentCopies = max(maximumConcurrentCopies, activeCopies)
        let delay = copyDelay
        lock.unlock()

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        return response
    }

    private func endCopy() {
        lock.lock()
        activeCopies -= 1
        lock.unlock()
    }

    private func resolve(_ response: Response?) throws -> AccessibilityValue {
        switch response {
        case let .value(value):
            return value
        case let .error(error):
            throw error
        case nil:
            throw AccessibilityAdapterError.ax(.noValue)
        }
    }
}
