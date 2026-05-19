// MARK: - MapLocalEditorMenuContent

enum MapLocalEditorMenuContent {
    static let methodSections: [[MapLocalHTTPMethod]] = [
        [.any],
        [.get, .post, .put, .delete, .patch],
        [.head, .options, .trace],
    ]

    static let matchTypeSections: [[MapLocalMatchType]] = [
        [.wildcard, .regex],
    ]

    static let delaySections: [[MapLocalDelayPreset]] = [
        [.none],
        [.oneSecond, .twoSeconds, .threeSeconds, .fiveSeconds, .tenSeconds, .thirtySeconds, .sixtySeconds],
        [.random],
        [.custom],
    ]
}
