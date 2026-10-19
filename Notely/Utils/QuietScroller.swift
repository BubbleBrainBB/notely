import AppKit

/// The app's scroller: no track, only a slim, faint rounded thumb, and
/// always the overlay kind that shows while scrolling — whatever "Show
/// scroll bars" is set to — so a page never carries a heavy gray bar.
final class QuietScroller: NSScroller {
    /// The sidebar draws a shortened thumb that reads as a mark; the editor
    /// keeps the true length, which shows where you are in a long note.
    var shortensKnob = false

    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 7 }

    override func drawKnob() {
        let slotRect = rect(for: .knobSlot)
        let rawKnobRect = rect(for: .knob).insetBy(dx: 0, dy: 2)
        let height = shortensKnob ? max(34, rawKnobRect.height * 0.66) : max(24, rawKnobRect.height)
        let knobRect = NSRect(x: slotRect.midX - 2, y: rawKnobRect.midY - height / 2, width: 4, height: height)
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: 2, yRadius: 2).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // No track: only the thumb.
    }
}
