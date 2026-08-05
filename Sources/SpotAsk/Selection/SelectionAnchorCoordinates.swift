import AppKit
import CoreGraphics
import Foundation

struct SelectionScreenCoordinateSpace: Equatable, Sendable {
    let displayBounds: CGRect
    let appKitFrame: CGRect
    let scaleFactor: CGFloat
}

protocol SelectionScreenProviding: Sendable {
    func coordinateSpaces() -> [SelectionScreenCoordinateSpace]
}

struct MacOSSelectionScreenProvider: SelectionScreenProviding {
    func coordinateSpaces() -> [SelectionScreenCoordinateSpace] {
        NSScreen.screens.compactMap { screen in
            let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
            guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            return SelectionScreenCoordinateSpace(
                displayBounds: CGDisplayBounds(displayID),
                appKitFrame: screen.frame,
                scaleFactor: screen.backingScaleFactor
            )
        }
    }
}

enum SelectionAnchorCoordinateConverter {
    static func appKitRect(
        fromAccessibilityRect rect: CGRect,
        coordinateSpaces: [SelectionScreenCoordinateSpace]
    ) -> CGRect? {
        guard !rect.isNull, !rect.isInfinite else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let coordinateSpace = coordinateSpaces.first(where: { $0.displayBounds.contains(center) }),
              coordinateSpace.scaleFactor > 0 else {
            return nil
        }

        let scale = coordinateSpace.scaleFactor
        let x = coordinateSpace.appKitFrame.minX + (rect.minX - coordinateSpace.displayBounds.minX) / scale
        let height = rect.height / scale
        let y = coordinateSpace.appKitFrame.maxY - (rect.minY - coordinateSpace.displayBounds.minY) / scale - height
        return CGRect(x: x, y: y, width: rect.width / scale, height: height)
    }
}
