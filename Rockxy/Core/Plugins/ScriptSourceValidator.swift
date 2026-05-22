import Foundation
import JavaScriptCore
import os

// MARK: - ScriptSourceValidationResult

enum ScriptSourceValidationResult: Equatable {
    case valid
    case invalid(String)
}

// MARK: - ScriptSourceValidator

enum ScriptSourceValidator {
    // MARK: Internal

    static func validate(
        source: String,
        runOnRequest: Bool,
        runOnResponse: Bool,
        runAsMock: Bool
    )
        -> ScriptSourceValidationResult
    {
        if !runOnRequest, !runOnResponse {
            return .invalid("Enable Request or Response before validating.")
        }
        if runAsMock, !runOnRequest {
            return .invalid("Mock API scripts must run on Request.")
        }

        guard let context = JSContext() else {
            return .invalid("Failed to create JavaScript context.")
        }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "Unknown JavaScript error"
        }

        let suiteName = "RockxyScriptValidation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptValidation")
        ScriptBridge.install(in: context, pluginID: "validation", logger: logger, defaults: defaults)

        context.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
        context.evaluateScript(source)

        if let exceptionMessage {
            return .invalid(exceptionMessage)
        }
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown JavaScript error"
            context.exception = nil
            return .invalid(message)
        }

        if runOnRequest, !hasHook(named: "onRequest", in: context) {
            return .invalid("Request is enabled, but onRequest is missing.")
        }
        if runOnResponse, !hasHook(named: "onResponse", in: context) {
            return .invalid("Response is enabled, but onResponse is missing.")
        }

        return .valid
    }

    // MARK: Private

    private static func hasHook(named name: String, in context: JSContext) -> Bool {
        let moduleObj = context.objectForKeyedSubscript("module")
        let moduleExports = moduleObj?.objectForKeyedSubscript("exports")
        if let exports = moduleExports,
           !exports.isUndefined,
           !exports.isNull,
           let fn = exports.objectForKeyedSubscript(name),
           !fn.isUndefined,
           fn.isObject
        {
            return true
        }
        if let global = context.objectForKeyedSubscript(name),
           !global.isUndefined,
           global.isObject
        {
            return true
        }
        return false
    }
}
