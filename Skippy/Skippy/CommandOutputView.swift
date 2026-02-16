import SwiftUI
import AppKit

/// A scrolling monospaced text view for displaying command output.
///
/// When scrolled to the bottom, the view stays pinned as new text is appended.
/// If the user scrolls away from the bottom, the scroll position remains fixed.
struct CommandOutputView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = NSColor.textBackgroundColor

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView else { return }
            context.coordinator.updateScrollPosition(scrollView: scrollView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard let layoutManager = textView.layoutManager else { return }
        guard let textContainer = textView.textContainer else { return }
        guard let textStorage = textView.textStorage else { return }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        textStorage.setAttributedString(NSAttributedString(string: text, attributes: attrs))

        if context.coordinator.isAtBottom {
            layoutManager.ensureLayout(for: textContainer)
            context.coordinator.isProgrammaticScroll = true
            textView.scrollToEndOfDocument(nil)
            DispatchQueue.main.async {
                context.coordinator.isProgrammaticScroll = false
            }
        }
    }

    class Coordinator {
        var isProgrammaticScroll = false
        var isAtBottom = true

        func updateScrollPosition(scrollView: NSScrollView) {
            if isProgrammaticScroll { return }
            guard let textView = scrollView.documentView else { return }

            let visibleRect = scrollView.contentView.bounds
            let textHeight = textView.bounds.height
            let scrollPosition = visibleRect.origin.y + visibleRect.height

            let atBottom = textHeight - scrollPosition < 10
            if isAtBottom != atBottom {
                isAtBottom = atBottom
            }
        }
    }
}
