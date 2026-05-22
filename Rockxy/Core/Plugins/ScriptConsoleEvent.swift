import Foundation

// MARK: - ScriptConsoleEventLevel

enum ScriptConsoleEventLevel: String, Sendable {
    case log
    case info
    case warn
    case error
    case debug
}

// MARK: - ScriptConsoleEvent

struct ScriptConsoleEvent: Equatable, Sendable {
    let pluginID: String
    let level: ScriptConsoleEventLevel
    let message: String
    let timestamp: Date
}
