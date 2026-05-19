// MARK: - ScriptEditorMenuContent

enum ScriptEditorMenuContent {
    static let methodSections: [[ScriptMatchMethod]] = [
        [.any],
        [.get, .post, .put, .delete, .patch],
        [.head, .options, .trace],
    ]

    static let patternModeSections: [[ScriptMatchPatternMode]] = [
        [.wildcard, .regex],
        [.advanced],
    ]
}
