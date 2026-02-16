import SwiftUI
import AppKit

/// A scrolling monospaced text view for displaying command output.
///
/// When scrolled to the bottom, the view stays pinned as new text is appended.
/// If the user scrolls away from the bottom, the scroll position remains fixed.
struct CommandOutputView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    var colorizeCheckupLines: Bool = false
    var logFileURL: URL? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

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

        if colorizeCheckupLines {
            textStorage.setAttributedString(colorizedCheckupString(text: text, font: font, logFileURL: logFileURL))
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
            textStorage.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        }

        if context.coordinator.isAtBottom {
            layoutManager.ensureLayout(for: textContainer)
            context.coordinator.isProgrammaticScroll = true
            textView.scrollToEndOfDocument(nil)
            DispatchQueue.main.async {
                context.coordinator.isProgrammaticScroll = false
            }
        }
    }

    private func colorizedCheckupString(text: String, font: NSFont, logFileURL: URL?) -> NSAttributedString {
        let defaultAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let result = NSMutableAttributedString()

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
            }

            let color: NSColor
            if line.hasPrefix("[✓]") {
                color = .systemGreen
            } else if line.hasPrefix("[✗]") {
                color = .systemRed
            } else if line.hasPrefix("[!]") {
                color = .systemOrange
            } else {
                color = .labelColor
            }

            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            result.append(NSAttributedString(string: line, attributes: attrs))
        }

        if let url = logFileURL {
            result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemBlue,
                .link: url
            ]
            result.append(NSAttributedString(string: "[→] Open Output Log", attributes: linkAttrs))
            result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
        }

        return result
    }

    class Coordinator: NSObject, NSTextViewDelegate {
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

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

/// Wraps ``CommandOutputView`` with an animated "Executing..." last line while a command is running.
struct AnimatedCommandOutputView: View {
    let text: String
    let fontSize: CGFloat
    var isExecuting: Bool = false
    var colorizeCheckupLines: Bool = false
    var logFileURL: URL? = nil

    @State private var dotCount = 0

    private var displayText: String {
        if isExecuting {
            text + "Executing" + String(repeating: ".", count: dotCount)
        } else {
            text
        }
    }

    var body: some View {
        CommandOutputView(text: displayText, fontSize: fontSize, colorizeCheckupLines: colorizeCheckupLines, logFileURL: logFileURL)
            .task(id: isExecuting) {
                guard isExecuting else { return }
                dotCount = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    dotCount = (dotCount + 1) % 4
                }
            }
    }
}
