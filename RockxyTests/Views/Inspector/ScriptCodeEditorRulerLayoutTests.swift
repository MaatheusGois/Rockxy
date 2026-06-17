import AppKit
@testable import Rockxy
import Testing

struct ScriptCodeEditorRulerLayoutTests {
    @Test("Visible text rect subtracts the text container origin from clip bounds")
    func visibleTextContainerRectUsesTextContainerOrigin() {
        let rect = ScriptCodeEditorRulerLayout.visibleTextContainerRect(
            contentBounds: NSRect(x: 12, y: 140, width: 320, height: 180),
            textContainerOrigin: NSPoint(x: 8, y: 10)
        )

        #expect(rect.origin.x == 4)
        #expect(rect.origin.y == 130)
        #expect(rect.width == 320)
        #expect(rect.height == 180)
    }

    @Test("Line number counts newlines before the target character")
    func lineNumberCountsNewlinesBeforeCharacter() {
        let content = "one\ntwo\nthree\nfour" as NSString

        #expect(ScriptCodeEditorRulerLayout.lineNumber(in: content, forCharacterAt: 0) == 1)
        #expect(ScriptCodeEditorRulerLayout.lineNumber(in: content, forCharacterAt: 4) == 2)
        #expect(ScriptCodeEditorRulerLayout.lineNumber(in: content, forCharacterAt: 8) == 3)
        #expect(ScriptCodeEditorRulerLayout.lineNumber(in: content, forCharacterAt: content.length) == 4)
    }

    @Test("Line number clamps character indexes outside content bounds")
    func lineNumberClampsOutOfBoundsCharacterIndexes() {
        let content = "one\ntwo" as NSString

        #expect(ScriptCodeEditorRulerLayout.lineNumber(in: content, forCharacterAt: -20) == 1)
        #expect(ScriptCodeEditorRulerLayout.lineNumber(in: content, forCharacterAt: 500) == 2)
    }

    @Test("Ruler y position follows text container origin and scroll offset")
    func rulerYAppliesScrollOffset() {
        let y = ScriptCodeEditorRulerLayout.rulerY(
            lineFragmentY: 240,
            textContainerOriginY: 8,
            contentOffsetY: 200
        )

        #expect(y == 48)
    }

    @Test("Label x position keeps a trailing gutter inset")
    func labelXUsesTrailingInset() {
        let x = ScriptCodeEditorRulerLayout.labelX(ruleThickness: 40, labelWidth: 18)

        #expect(x == 18)
    }

    @Test("Ruler gutter scales with editor font size")
    @MainActor
    func rulerGutterScalesWithEditorFontSize() {
        let textView = NSTextView()
        let ruler = ScriptCodeEditorRulerView(textView: textView)
        let defaultThickness = ruler.ruleThickness

        ruler.applyEditorSettings(InspectorTextEditorSettings(fontSize: 28, useMonospacedFont: true))

        #expect(ruler.ruleThickness > defaultThickness)
    }
}
