import AppKit
@preconcurrency import SwiftTerm

final class VeloxTerminalView: TerminalView {
    private var mouseMovedMonitor: Any?

    deinit {
        removeMouseMovedMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeMouseMovedMonitor()
        } else {
            installMouseMovedMonitorIfNeeded()
        }
    }

    private func installMouseMovedMonitorIfNeeded() {
        guard mouseMovedMonitor == nil else {
            return
        }

        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, self.shouldSuppressMouseMoved(event) else {
                return event
            }

            return nil
        }
    }

    private func removeMouseMovedMonitor() {
        guard let mouseMovedMonitor else {
            return
        }

        NSEvent.removeMonitor(mouseMovedMonitor)
        self.mouseMovedMonitor = nil
    }

    fileprivate func shouldSuppressMouseMoved(_ event: NSEvent) -> Bool {
        guard !allowMouseReporting, event.window === window else {
            return false
        }

        return bounds.contains(convert(event.locationInWindow, from: nil))
    }
}

final class VeloxLocalProcessTerminalView: LocalProcessTerminalView {
    private var mouseMovedMonitor: Any?

    deinit {
        removeMouseMovedMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeMouseMovedMonitor()
        } else {
            installMouseMovedMonitorIfNeeded()
        }
    }

    private func installMouseMovedMonitorIfNeeded() {
        guard mouseMovedMonitor == nil else {
            return
        }

        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, self.shouldSuppressMouseMoved(event) else {
                return event
            }

            return nil
        }
    }

    private func removeMouseMovedMonitor() {
        guard let mouseMovedMonitor else {
            return
        }

        NSEvent.removeMonitor(mouseMovedMonitor)
        self.mouseMovedMonitor = nil
    }

    private func shouldSuppressMouseMoved(_ event: NSEvent) -> Bool {
        guard !allowMouseReporting, event.window === window else {
            return false
        }

        return bounds.contains(convert(event.locationInWindow, from: nil))
    }
}
