import AppKit

@MainActor
final class SelectionAutoInvokeMonitor {
    private let coordinator: SelectionAssistantCoordinator
    private var monitor: Any?

    init(coordinator: SelectionAssistantCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.type == .leftMouseDown {
                    self.coordinator.cancelAutomaticTrigger()
                } else {
                    self.coordinator.scheduleAutomaticTrigger()
                }
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
