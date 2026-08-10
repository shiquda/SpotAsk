import AppKit

@MainActor
final class SelectionAutoInvokeMonitor {
    private let coordinator: SelectionAssistantCoordinator
    private var monitor: Any?
    private var mouseDownLocation: CGPoint?

    init(coordinator: SelectionAssistantCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.type == .leftMouseDown {
                    self.mouseDownLocation = Self.globalLocation(for: event)
                    self.coordinator.cancelAutomaticTrigger()
                } else {
                    let shouldTrigger = SelectionAutoInvokeGesture.shouldTrigger(
                        mouseDownLocation: self.mouseDownLocation,
                        mouseUpLocation: Self.globalLocation(for: event),
                        clickCount: event.clickCount,
                        modifierFlags: event.modifierFlags
                    )
                    self.mouseDownLocation = nil
                    if shouldTrigger {
                        self.coordinator.scheduleAutomaticTrigger()
                    }
                }
            }
        }
    }

    private static func globalLocation(for event: NSEvent) -> CGPoint {
        event.cgEvent?.location ?? NSEvent.mouseLocation
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

enum SelectionAutoInvokeGesture {
    private static let dragThreshold: CGFloat = 3

    static func shouldTrigger(
        mouseDownLocation: CGPoint?,
        mouseUpLocation: CGPoint,
        clickCount: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        if clickCount >= 2 || modifierFlags.contains(.shift) {
            return true
        }
        guard let mouseDownLocation else { return false }
        return hypot(
            mouseUpLocation.x - mouseDownLocation.x,
            mouseUpLocation.y - mouseDownLocation.y
        ) >= dragThreshold
    }
}
