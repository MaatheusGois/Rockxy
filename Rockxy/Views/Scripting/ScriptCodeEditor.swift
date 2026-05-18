import AppKit
import SwiftUI

// MARK: - ScriptCodeEditor

/// NSTextView-backed code editor with a line-number ruler. Monospaced 13pt,
/// find-bar enabled, automatic substitutions disabled so JS syntax characters
/// aren't mangled. Used by `ScriptEditorWindowView`.
struct ScriptCodeEditor: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(text: Binding<String>) {
            self.text = text
        }

        // MARK: Internal

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
        }

        // MARK: Private

        private var text: Binding<String>
    }

    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isRichText = false
        textView.delegate = context.coordinator

        let ruler = ScriptCodeEditorRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context _: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
            (nsView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
}

// MARK: - ScriptCodeEditorRulerView

/// Draws monospaced line numbers alongside the code editor. Re-renders on
/// text changes, scroll bounds changes, and text view layout changes.
final class ScriptCodeEditorRulerView: NSRulerView {
    // MARK: Lifecycle

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView
        scrollView?.contentView.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateLineNumbers),
            name: NSText.didChangeNotification,
            object: textView
        )
        if let contentView = scrollView?.contentView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(invalidateLineNumbers),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateLineNumbers),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Internal

    override func drawHashMarksAndLabels(in rect: NSRect) {
        let dirtyRect = bounds.intersection(rect)
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        NSGraphicsContext.current?.saveGraphicsState()
        dirtyRect.clip()
        defer {
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let contentView = scrollView?.contentView else
        {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let content = textView.string as NSString
        let visibleRect = ScriptCodeEditorRulerLayout.visibleTextContainerRect(
            contentBounds: contentView.bounds,
            textContainerOrigin: textView.textContainerOrigin
        )
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        var glyphIndex = visibleGlyphRange.location
        var lastLineRange = NSRange(location: NSNotFound, length: 0)
        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            if lineRange.location == lastLineRange.location, lineRange.length == lastLineRange.length {
                glyphIndex = max(NSMaxRange(lineGlyphRange), glyphIndex + 1)
                continue
            }
            lastLineRange = lineRange

            var effectiveGlyphRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveGlyphRange,
                withoutAdditionalLayout: true
            )
            let lineNumber = ScriptCodeEditorRulerLayout.lineNumber(
                in: content,
                forCharacterAt: lineRange.location
            )

            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            let y = ScriptCodeEditorRulerLayout.rulerY(
                lineFragmentY: lineRect.origin.y,
                textContainerOriginY: textView.textContainerOrigin.y,
                contentOffsetY: contentView.bounds.origin.y
            )
            str.draw(
                at: NSPoint(
                    x: ScriptCodeEditorRulerLayout.labelX(ruleThickness: ruleThickness, labelWidth: size.width),
                    y: y
                ),
                withAttributes: attrs
            )

            let nextGlyphIndex = max(NSMaxRange(lineGlyphRange), NSMaxRange(effectiveGlyphRange), glyphIndex + 1)
            glyphIndex = nextGlyphIndex
        }
    }

    @objc
    func invalidateLineNumbers() {
        needsDisplay = true
        setNeedsDisplay(bounds)
    }

    // MARK: Private

    private weak var textView: NSTextView?
}

// MARK: - ScriptCodeEditorRulerLayout

enum ScriptCodeEditorRulerLayout {
    static let labelTrailingPadding: CGFloat = 4

    static func visibleTextContainerRect(contentBounds: NSRect, textContainerOrigin: NSPoint) -> NSRect {
        NSRect(
            x: contentBounds.origin.x - textContainerOrigin.x,
            y: contentBounds.origin.y - textContainerOrigin.y,
            width: contentBounds.width,
            height: contentBounds.height
        )
    }

    static func lineNumber(in content: NSString, forCharacterAt characterIndex: Int) -> Int {
        let end = min(max(characterIndex, 0), content.length)
        guard end > 0 else {
            return 1
        }

        var lineNumber = 1
        var index = 0
        while index < end {
            if content.character(at: index) == 0x0A {
                lineNumber += 1
            }
            index += 1
        }
        return lineNumber
    }

    static func rulerY(lineFragmentY: CGFloat, textContainerOriginY: CGFloat, contentOffsetY: CGFloat) -> CGFloat {
        lineFragmentY + textContainerOriginY - contentOffsetY
    }

    static func labelX(ruleThickness: CGFloat, labelWidth: CGFloat) -> CGFloat {
        max(0, ruleThickness - labelWidth - labelTrailingPadding)
    }
}
