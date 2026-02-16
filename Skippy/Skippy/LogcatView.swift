import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Displays the tail of `adb logcat`.
struct LogcatView: View {
    @State private var logcatManager = LogcatManager()
    @State private var minLevel: String = "V"
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Int = 0
    @State private var filterText: String = ""
    @State private var isSearchVisible = false
    @State private var searchText = ""
    @State private var currentMatchIndex = 0
    @State private var totalMatchCount = 0

    private static let baseFontSize: CGFloat = 11
    private var fontSize: CGFloat {
        max(6, min(30, Self.baseFontSize + CGFloat(fontSizeOffset)))
    }
    
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isSearchVisible {
                HStack(spacing: 8) {
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                        .focused($isSearchFieldFocused)
                        .onSubmit { advanceMatch(forward: true) }
                    Text(totalMatchCount > 0 ? "\(currentMatchIndex + 1)/\(totalMatchCount)" : "0/0")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .center)
                    Button(action: { advanceMatch(forward: false) }) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(totalMatchCount == 0)
                    Button(action: { advanceMatch(forward: true) }) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(totalMatchCount == 0)
                    Button(action: dismissSearch) {
                        Image(systemName: "xmark")
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error = logcatManager.errorMessage {
                Text(error)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LogcatScrollView(
                    entries: logcatManager.entries,
                    isAtBottom: $logcatManager.isAtBottom,
                    minLevel: minLevel,
                    filterText: filterText,
                    fontSize: fontSize,
                    searchText: isSearchVisible ? searchText : "",
                    currentMatchIndex: currentMatchIndex,
                    totalMatchCount: $totalMatchCount
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(WindowFrameSaver(name: "logcatWindow"))
        .navigationTitle("Logcat")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            ToolbarItem(placement: .automatic) {
                Picker("", selection: $minLevel) {
                    ForEach(LogcatEntry.Level.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: saveLog) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    logcatManager.clearLog()
                }) {
                    Label("Clear", systemImage: "trash")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    if isSearchVisible { dismissSearch() } else { activateSearch() }
                }) {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
        .onAppear {
            logcatManager.startLogcat()
        }
        .onDisappear {
            logcatManager.stopLogcat()
        }
        .onChange(of: searchText) {
            currentMatchIndex = 0
        }
        .onChange(of: totalMatchCount) {
            if totalMatchCount == 0 {
                currentMatchIndex = 0
            } else if currentMatchIndex >= totalMatchCount {
                currentMatchIndex = totalMatchCount - 1
            }
        }
        .focusedSceneValue(\.searchCommands, SearchCommands(
            activate: { activateSearch() },
            next: { advanceMatch(forward: true) },
            previous: { advanceMatch(forward: false) },
            hasMatches: isSearchVisible && totalMatchCount > 0
        ))
    }

    private func activateSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchVisible = true
        }
        logcatManager.isSearchActive = true
        isSearchFieldFocused = true
    }

    private func dismissSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchVisible = false
        }
        searchText = ""
        currentMatchIndex = 0
        totalMatchCount = 0
        logcatManager.isSearchActive = false
    }

    private func advanceMatch(forward: Bool) {
        guard totalMatchCount > 0 else { return }
        if forward {
            currentMatchIndex = (currentMatchIndex + 1) % totalMatchCount
        } else {
            currentMatchIndex = (currentMatchIndex - 1 + totalMatchCount) % totalMatchCount
        }
    }

    private func saveLog() {
        let allEntries = logcatManager.entries
        let hasFilter = minLevel != "V" || !filterText.trimmingCharacters(in: .whitespaces).isEmpty

        // Snapshot both versions immediately so new output doesn't affect them
        let allText = allEntries.map(\.rawText).joined(separator: "\n")
        let filteredText = hasFilter ? filteredEntries(from: allEntries).map(\.rawText).joined(separator: "\n") : nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "logcat.txt"

        var popup: NSPopUpButton?
        if hasFilter {
            let button = NSPopUpButton(frame: .zero, pullsDown: false)
            button.addItems(withTitles: ["All Entries", "Filtered Entries"])
            let preferFiltered = UserDefaults.standard.bool(forKey: "saveLogFiltered")
            button.selectItem(at: preferFiltered ? 1 : 0)
            button.sizeToFit()
            panel.accessoryView = button
            popup = button
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let useFiltered: Bool
            if let popup {
                useFiltered = popup.indexOfSelectedItem == 1
                UserDefaults.standard.set(useFiltered, forKey: "saveLogFiltered")
            } else {
                useFiltered = false
            }
            let text = useFiltered ? (filteredText ?? allText) : allText
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func filteredEntries(from entries: [LogcatEntry]) -> [LogcatEntry] {
        let minLogLevel = LogcatEntry.Level(rawValue: minLevel)
        let searchText = filterText.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            if let minLogLevel, let level = entry.level {
                guard level >= minLogLevel else { return false }
            } else if minLogLevel != nil {
                return false
            }
            if !searchText.isEmpty {
                guard entry.rawText.localizedCaseInsensitiveContains(searchText) else { return false }
            }
            return true
        }
    }
}

struct SearchCommands {
    var activate: () -> Void
    var next: () -> Void
    var previous: () -> Void
    var hasMatches: Bool
}

private struct SearchCommandsKey: FocusedValueKey {
    typealias Value = SearchCommands
}

extension FocusedValues {
    var searchCommands: SearchCommands? {
        get { self[SearchCommandsKey.self] }
        set { self[SearchCommandsKey.self] = newValue }
    }
}

/// Sets `NSWindow.setFrameAutosaveName` on the hosting window so AppKit
/// automatically persists and restores the window's size and position.
struct WindowFrameSaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct LogcatScrollView: NSViewRepresentable {
    let entries: [LogcatEntry]
    @Binding var isAtBottom: Bool
    let minLevel: String
    let filterText: String
    let fontSize: CGFloat
    let searchText: String
    let currentMatchIndex: Int
    @Binding var totalMatchCount: Int
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure text view
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        // Track scroll position changes
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView = scrollView else { return }
            context.coordinator.updateScrollPosition(scrollView: scrollView, isAtBotomBinding: $isAtBottom)
        }
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard let layoutManager = textView.layoutManager else { return }
        guard let textContainer = textView.textContainer else { return }
        guard let textStorage = textView.textStorage else { return }

        // Filter and colorize entries based on minimum log level
        let filtered = filterEntries(entries, minLevel: minLevel, filterText: filterText)
        let colorized = colorizeEntries(filtered, highlightText: filterText, searchText: searchText, currentMatchIndex: currentMatchIndex, fontSize: fontSize)

        // Update text storage
        textStorage.setAttributedString(colorized.attributedString)

        // Write back total match count (deferred to avoid re-render loop)
        let newCount = colorized.searchMatchRanges.count
        if newCount != totalMatchCount {
            DispatchQueue.main.async {
                self.totalMatchCount = newCount
            }
        }

        // Search scroll takes priority over auto-scroll-to-bottom
        let searchTerm = searchText.trimmingCharacters(in: .whitespaces)
        if !searchTerm.isEmpty && currentMatchIndex < colorized.searchMatchRanges.count {
            let matchRange = colorized.searchMatchRanges[currentMatchIndex]
            layoutManager.ensureLayout(for: textContainer)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: matchRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: textView.textContainerInset.width, dy: textView.textContainerInset.height)

            context.coordinator.isProgrammaticScroll = true
            textView.scrollToVisible(rect.insetBy(dx: 0, dy: -20))
            DispatchQueue.main.async {
                context.coordinator.isProgrammaticScroll = false
            }
        } else if isAtBottom {
            layoutManager.ensureLayout(for: textContainer)
            textView.scrollToEndOfDocument(nil)
        }
    }
    
    private func filterEntries(_ entries: [LogcatEntry], minLevel: String, filterText: String) -> [LogcatEntry] {
        let minLogLevel = LogcatEntry.Level(rawValue: minLevel)
        let searchText = filterText.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            if let minLogLevel, let level = entry.level {
                guard level >= minLogLevel else { return false }
            } else if minLogLevel != nil {
                return false
            }
            if !searchText.isEmpty {
                guard entry.rawText.localizedCaseInsensitiveContains(searchText) else { return false }
            }
            return true
        }
    }

    private struct ColorizeResult {
        let attributedString: NSAttributedString
        let searchMatchRanges: [NSRange]
    }

    private func colorizeEntries(_ entries: [LogcatEntry], highlightText: String, searchText: String, currentMatchIndex: Int, fontSize: CGFloat) -> ColorizeResult {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let filterTerm = highlightText.trimmingCharacters(in: .whitespaces)
        let searchTerm = searchText.trimmingCharacters(in: .whitespaces)
        let result = NSMutableAttributedString()
        var searchMatchRanges: [NSRange] = []

        for (index, entry) in entries.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            let globalOffset = result.length
            let color = entry.level?.color ?? NSColor.labelColor
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let entryStr = NSMutableAttributedString(string: entry.rawText, attributes: attrs)

            // Filter text highlighting
            if !filterTerm.isEmpty {
                let text = entry.rawText as NSString
                var range = NSRange(location: 0, length: text.length)
                while range.location < text.length {
                    let found = text.range(of: filterTerm, options: .caseInsensitive, range: range)
                    guard found.location != NSNotFound else { break }
                    entryStr.addAttribute(.backgroundColor, value: NSColor.findHighlightColor, range: found)
                    range.location = found.location + found.length
                    range.length = text.length - range.location
                }
            }

            // Search text highlighting (overwrites filter highlight where they overlap)
            if !searchTerm.isEmpty {
                let text = entry.rawText as NSString
                var range = NSRange(location: 0, length: text.length)
                while range.location < text.length {
                    let found = text.range(of: searchTerm, options: .caseInsensitive, range: range)
                    guard found.location != NSNotFound else { break }
                    let globalRange = NSRange(location: globalOffset + found.location, length: found.length)
                    let matchIdx = searchMatchRanges.count
                    searchMatchRanges.append(globalRange)

                    if matchIdx == currentMatchIndex {
                        entryStr.addAttribute(.backgroundColor, value: NSColor.controlAccentColor, range: found)
                        entryStr.addAttribute(.foregroundColor, value: NSColor.white, range: found)
                    } else {
                        entryStr.addAttribute(.backgroundColor, value: NSColor.findHighlightColor, range: found)
                    }
                    range.location = found.location + found.length
                    range.length = text.length - range.location
                }
            }

            result.append(entryStr)
        }

        return ColorizeResult(attributedString: result, searchMatchRanges: searchMatchRanges)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var isProgrammaticScroll = false

        func updateScrollPosition(scrollView: NSScrollView, isAtBotomBinding: Binding<Bool>) {
            if isProgrammaticScroll { return }

            guard let textView = scrollView.documentView else { return }

            let visibleRect = scrollView.contentView.bounds
            let textHeight = textView.bounds.height
            let scrollPosition = visibleRect.origin.y + visibleRect.height

            // Consider "at bottom" if within 10 points of the bottom
            let atBottom = textHeight - scrollPosition < 10

            if isAtBotomBinding.wrappedValue != atBottom {
                isAtBotomBinding.wrappedValue = atBottom
            }
        }
    }
}


