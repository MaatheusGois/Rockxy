import AppKit
import SwiftUI

// MARK: - MapLocalHTTPMessageEditor

struct MapLocalHTTPMessageEditor: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(text: Binding<String>, editorSettings: InspectorTextEditorSettings) {
            self.text = text
            self.editorSettings = editorSettings
        }

        deinit {
            highlightTask?.cancel()
        }

        // MARK: Internal

        var isProgrammaticChange = false
        var editorSettings: InspectorTextEditorSettings
        var highlightTask: Task<Void, Never>?

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange,
                  let textView = notification.object as? NSTextView,
                  let scrollView = textView.enclosingScrollView else
            {
                return
            }
            text.wrappedValue = textView.string
            (scrollView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
            scheduleHighlight(text: textView.string, editorSettings: editorSettings, in: scrollView)
        }

        @MainActor
        func scheduleHighlight(
            text: String,
            editorSettings: InspectorTextEditorSettings,
            in scrollView: NSScrollView
        ) {
            highlightTask?.cancel()
            self.editorSettings = editorSettings
            highlightTask = Task { [weak self, weak scrollView] in
                let spans = await Task.detached(priority: .utility) {
                    Self.highlightSpans(for: text)
                }.value

                guard !Task.isCancelled,
                      let self,
                      let scrollView,
                      let textView = scrollView.documentView as? NSTextView,
                      textView.string == text else
                {
                    return
                }

                let selectedRange = textView.selectedRange()
                let attributed = Self.baseAttributedString(text, editorSettings: editorSettings)
                for span in spans where NSMaxRange(span.range) <= attributed.length {
                    attributed.addAttribute(.foregroundColor, value: span.role.color, range: span.range)
                }
                isProgrammaticChange = true
                textView.textStorage?.setAttributedString(attributed)
                textView.setSelectedRange(Self.clamped(range: selectedRange, length: attributed.length))
                textView.typingAttributes = Self.typingAttributes(editorSettings: editorSettings)
                isProgrammaticChange = false
                (scrollView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
            }
        }

        static func clamped(range: NSRange, length: Int) -> NSRange {
            guard range.location != NSNotFound else {
                return NSRange(location: 0, length: 0)
            }
            let location = min(range.location, length)
            let upperBound = min(range.location + range.length, length)
            return NSRange(location: location, length: max(0, upperBound - location))
        }

        // MARK: Private

        private var text: Binding<String>

        static func typingAttributes(editorSettings: InspectorTextEditorSettings) -> [NSAttributedString.Key: Any] {
            [
                .font: editorSettings.appKitFont,
                .foregroundColor: NSColor.textColor,
                .backgroundColor: NSColor.textBackgroundColor,
                .paragraphStyle: paragraphStyle(for: editorSettings),
            ]
        }

        private static func baseAttributedString(
            _ text: String,
            editorSettings: InspectorTextEditorSettings
        )
            -> NSMutableAttributedString
        {
            NSMutableAttributedString(string: text, attributes: typingAttributes(editorSettings: editorSettings))
        }

        private static func paragraphStyle(for editorSettings: InspectorTextEditorSettings) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.defaultTabInterval = editorSettings.tabInterval
            return style
        }

        nonisolated private static func highlightSpans(for text: String) -> [HighlightSpan] {
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            var spans: [HighlightSpan] = []
            appendSpans(
                #"(?m)^HTTP/\d(?:\.\d)?\s+\d{3}(?:\s+[A-Za-z ]+)?"#,
                role: .status,
                text: text,
                range: fullRange,
                spans: &spans
            )
            appendSpans(
                #"(?m)^(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|TRACE)\s+\S+\s+HTTP/\d(?:\.\d)?"#,
                role: .status,
                text: text,
                range: fullRange,
                spans: &spans
            )
            appendSpans(
                #"(?m)^[A-Za-z0-9!#$%&'*+.^_`|~-]+:"#,
                role: .header,
                text: text,
                range: fullRange,
                spans: &spans
            )
            appendSpans(#""(?:\\.|[^"\\])*"(?=\s*:)"#, role: .key, text: text, range: fullRange, spans: &spans)
            appendSpans(#""(?:\\.|[^"\\])*""#, role: .string, text: text, range: fullRange, spans: &spans)
            appendSpans(
                #"(?<![\w.])-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#,
                role: .number,
                text: text,
                range: fullRange,
                spans: &spans
            )
            appendSpans(#"\b(?:true|false)\b"#, role: .bool, text: text, range: fullRange, spans: &spans)
            appendSpans(#"\bnull\b"#, role: .null, text: text, range: fullRange, spans: &spans)
            appendSpans(#"[\{\}\[\],:]"#, role: .bracket, text: text, range: fullRange, spans: &spans)
            return spans
        }

        nonisolated private static func appendSpans(
            _ pattern: String,
            role: HighlightRole,
            text: String,
            range: NSRange,
            spans: inout [HighlightSpan]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return
            }
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else {
                    return
                }
                spans.append(HighlightSpan(range: match.range, role: role))
            }
        }

        private struct HighlightSpan: Sendable {
            let range: NSRange
            let role: HighlightRole
        }

        private enum HighlightRole: Sendable {
            case status
            case header
            case key
            case string
            case number
            case bool
            case null
            case bracket

            @MainActor var color: NSColor {
                switch self {
                case .status: Theme.JSON.statusNS
                case .header: Theme.JSON.headerNS
                case .key: Theme.JSON.keyNS
                case .string: Theme.JSON.stringNS
                case .number: Theme.JSON.numberNS
                case .bool: Theme.JSON.boolNS
                case .null: Theme.JSON.nullNS
                case .bracket: Theme.JSON.bracketNS
                }
            }
        }
    }

    @Binding var text: String
    var editorSettings = InspectorTextEditorSettings(useMonospacedFont: true, wordWrap: false)

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, editorSettings: editorSettings)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        configure(scrollView, coordinator: context.coordinator)
        apply(text, to: scrollView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        let settingsChanged = context.coordinator.editorSettings != editorSettings
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            let visibleOrigin = nsView.contentView.bounds.origin
            apply(text, to: nsView, coordinator: context.coordinator)
            textView.setSelectedRange(Coordinator.clamped(range: selectedRange, length: (text as NSString).length))
            nsView.contentView.scroll(to: visibleOrigin)
            nsView.reflectScrolledClipView(nsView.contentView)
        } else if settingsChanged {
            let selectedRange = textView.selectedRange()
            let visibleOrigin = nsView.contentView.bounds.origin
            applyEditorSettings(to: nsView)
            context.coordinator.scheduleHighlight(text: text, editorSettings: editorSettings, in: nsView)
            textView.setSelectedRange(Coordinator.clamped(range: selectedRange, length: (text as NSString).length))
            nsView.contentView.scroll(to: visibleOrigin)
            nsView.reflectScrolledClipView(nsView.contentView)
        }
    }

    private func configure(_ scrollView: NSScrollView, coordinator: Coordinator) {
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.masksToBounds = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = editorSettings.appKitFont
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 7)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.delegate = coordinator

        let ruler = ScriptCodeEditorRulerView(textView: textView)
        ruler.applyEditorSettings(editorSettings)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }

    private func apply(_ text: String, to scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        coordinator.isProgrammaticChange = true
        textView.string = text
        textView.font = editorSettings.appKitFont
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        coordinator.isProgrammaticChange = false
        applyEditorSettings(to: scrollView)
        coordinator.scheduleHighlight(text: text, editorSettings: editorSettings, in: scrollView)
        (scrollView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
    }

    private func applyEditorSettings(to scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        textView.font = editorSettings.appKitFont
        textView.typingAttributes = Coordinator.typingAttributes(editorSettings: editorSettings)
        textView.textContainerInset = NSSize(width: 8, height: 7)
        (scrollView.verticalRulerView as? ScriptCodeEditorRulerView)?.applyEditorSettings(editorSettings)
    }
}
