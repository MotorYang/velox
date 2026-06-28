import AppKit
import ObjectiveC

enum TerminalChromeStyler {
    private static var hoverControllerKey: UInt8 = 0
    private static let restingWidth: CGFloat = 7
    private static let hoverWidth: CGFloat = 12

    static func apply(to rootView: NSView) {
        styleScrollers(in: rootView)
    }

    private static func styleScrollers(in view: NSView) {
        if let scroller = view as? NSScroller {
            style(scroller)
        }

        for subview in view.subviews {
            styleScrollers(in: subview)
        }
    }

    private static func style(_ scroller: NSScroller) {
        let controller = hoverController(for: scroller)
        controller.installIfNeeded()
        applyScrollerState(scroller, isHovering: controller.isHovering)
    }

    fileprivate static func applyScrollerState(_ scroller: NSScroller, isHovering: Bool) {
        scroller.scrollerStyle = .overlay
        scroller.controlSize = .small
        scroller.knobStyle = .light
        scroller.alphaValue = isHovering ? 0.68 : 0.42
        scroller.wantsLayer = true
        scroller.layer?.backgroundColor = NSColor.clear.cgColor

        let width = isHovering ? hoverWidth : restingWidth
        for constraint in scroller.constraints where constraint.firstAttribute == .width {
            constraint.constant = width
        }

        guard let superview = scroller.superview else { return }
        for constraint in superview.constraints where constraint.firstAttribute == .width {
            if constraint.firstItem === scroller || constraint.secondItem === scroller {
                constraint.constant = width
            }
        }

        superview.needsLayout = true
        superview.layoutSubtreeIfNeeded()
        scroller.needsDisplay = true
    }

    private static func hoverController(for scroller: NSScroller) -> TerminalScrollerHoverController {
        if let controller = objc_getAssociatedObject(scroller, &hoverControllerKey) as? TerminalScrollerHoverController {
            return controller
        }

        let controller = TerminalScrollerHoverController(scroller: scroller)
        objc_setAssociatedObject(scroller, &hoverControllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }
}

@objc(TerminalScrollerHoverController)
private final class TerminalScrollerHoverController: NSObject {
    weak var scroller: NSScroller?
    private var trackingArea: NSTrackingArea?
    private var didPushCursor = false
    fileprivate private(set) var isHovering = false

    init(scroller: NSScroller) {
        self.scroller = scroller
    }

    func installIfNeeded() {
        guard let scroller else { return }
        if trackingArea != nil { return }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        scroller.addTrackingArea(area)
        trackingArea = area
    }

    @objc(mouseEntered:)
    func mouseEntered(_ event: NSEvent) {
        guard let scroller else { return }
        isHovering = true
        TerminalChromeStyler.applyScrollerState(scroller, isHovering: true)
        if !didPushCursor {
            NSCursor.pointingHand.push()
            didPushCursor = true
        }
    }

    @objc(mouseExited:)
    func mouseExited(_ event: NSEvent) {
        guard let scroller else { return }
        isHovering = false
        TerminalChromeStyler.applyScrollerState(scroller, isHovering: false)
        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
    }

    deinit {
        if didPushCursor {
            NSCursor.pop()
        }
    }
}
