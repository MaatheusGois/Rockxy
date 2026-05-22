import CryptoKit
import Foundation
import JavaScriptCore
import os

// Implements script bridge behavior for the plugin and scripting subsystem.

// MARK: - ScriptBridge

enum ScriptBridge {
    // MARK: Internal

    static func install(
        in context: JSContext,
        pluginID: String,
        logger: Logger,
        defaults: UserDefaults = .standard,
        consoleSink: (@Sendable (ScriptConsoleEvent) -> Void)? = nil
    ) {
        let rockxy = JSValue(newObjectIn: context)

        installLogging(on: rockxy, context: context, pluginID: pluginID, logger: logger, consoleSink: consoleSink)
        installCrypto(on: rockxy, context: context)
        installEncoding(on: rockxy, context: context)
        installStorage(on: rockxy, context: context, pluginID: pluginID, defaults: defaults)
        installEnv(on: rockxy, context: context, pluginID: pluginID, defaults: defaults)

        context.setObject(rockxy, forKeyedSubscript: "$rockxy" as NSString)
        installConsole(in: context, pluginID: pluginID, logger: logger, consoleSink: consoleSink)
    }

    // MARK: Private

    private static let bridgeLogger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptBridge")

    private static func installLogging(
        on rockxy: JSValue?,
        context: JSContext,
        pluginID: String,
        logger: Logger,
        consoleSink: (@Sendable (ScriptConsoleEvent) -> Void)?
    ) {
        let log = JSValue(newObjectIn: context)

        let infoFn: @convention(block) (String) -> Void = { msg in
            emitConsoleEvent(pluginID: pluginID, level: .info, message: msg, logger: logger, consoleSink: consoleSink)
        }
        let warnFn: @convention(block) (String) -> Void = { msg in
            emitConsoleEvent(pluginID: pluginID, level: .warn, message: msg, logger: logger, consoleSink: consoleSink)
        }
        let errorFn: @convention(block) (String) -> Void = { msg in
            emitConsoleEvent(pluginID: pluginID, level: .error, message: msg, logger: logger, consoleSink: consoleSink)
        }
        let debugFn: @convention(block) (String) -> Void = { msg in
            emitConsoleEvent(pluginID: pluginID, level: .debug, message: msg, logger: logger, consoleSink: consoleSink)
        }

        log?.setObject(infoFn, forKeyedSubscript: "info" as NSString)
        log?.setObject(warnFn, forKeyedSubscript: "warn" as NSString)
        log?.setObject(errorFn, forKeyedSubscript: "error" as NSString)
        log?.setObject(debugFn, forKeyedSubscript: "debug" as NSString)

        rockxy?.setObject(log, forKeyedSubscript: "log" as NSString)
    }

    private static func installConsole(
        in context: JSContext,
        pluginID: String,
        logger: Logger,
        consoleSink: (@Sendable (ScriptConsoleEvent) -> Void)?
    ) {
        let emitFn: @convention(block) (String, String) -> Void = { level, message in
            let eventLevel = ScriptConsoleEventLevel(rawValue: level) ?? .log
            emitConsoleEvent(
                pluginID: pluginID,
                level: eventLevel,
                message: message,
                logger: logger,
                consoleSink: consoleSink
            )
        }
        context.setObject(emitFn, forKeyedSubscript: "__rockxyNativeConsole" as NSString)
        context.evaluateScript(
            """
            (function () {
              function formatArg(value) {
                if (typeof value === "string") { return value; }
                if (value === null) { return "null"; }
                if (typeof value === "undefined") { return "undefined"; }
                try {
                  var json = JSON.stringify(value);
                  return typeof json === "undefined" ? String(value) : json;
                } catch (error) {
                  return String(value);
                }
              }
              function emit(level, args) {
                __rockxyNativeConsole(level, Array.prototype.map.call(args, formatArg).join(" "));
              }
              console = {
                log: function () { emit("log", arguments); },
                info: function () { emit("info", arguments); },
                warn: function () { emit("warn", arguments); },
                error: function () { emit("error", arguments); },
                debug: function () { emit("debug", arguments); }
              };
            }());
            """
        )
    }

    private static func emitConsoleEvent(
        pluginID: String,
        level: ScriptConsoleEventLevel,
        message: String,
        logger: Logger,
        consoleSink: (@Sendable (ScriptConsoleEvent) -> Void)?
    ) {
        switch level {
        case .log,
             .info:
            logger.info("[\(pluginID)] \(message)")
        case .warn:
            logger.warning("[\(pluginID)] \(message)")
        case .error:
            logger.error("[\(pluginID)] \(message)")
        case .debug:
            logger.debug("[\(pluginID)] \(message)")
        }
        consoleSink?(ScriptConsoleEvent(pluginID: pluginID, level: level, message: message, timestamp: .now))
    }

    private static func installCrypto(on rockxy: JSValue?, context: JSContext) {
        let crypto = JSValue(newObjectIn: context)

        let sha256Fn: @convention(block) (String) -> String = { input in
            let digest = SHA256.hash(data: Data(input.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        let md5Fn: @convention(block) (String) -> String = { input in
            let digest = Insecure.MD5.hash(data: Data(input.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        crypto?.setObject(sha256Fn, forKeyedSubscript: "sha256" as NSString)
        crypto?.setObject(md5Fn, forKeyedSubscript: "md5" as NSString)

        rockxy?.setObject(crypto, forKeyedSubscript: "crypto" as NSString)
    }

    private static func installEncoding(on rockxy: JSValue?, context: JSContext) {
        let encoding = JSValue(newObjectIn: context)

        let base64EncodeFn: @convention(block) (String) -> String = { input in
            Data(input.utf8).base64EncodedString()
        }
        let base64DecodeFn: @convention(block) (String) -> String = { input in
            guard let data = Data(base64Encoded: input),
                  let decoded = String(data: data, encoding: .utf8) else
            {
                return ""
            }
            return decoded
        }
        let urlEncodeFn: @convention(block) (String) -> String = { input in
            input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        }
        let urlDecodeFn: @convention(block) (String) -> String = { input in
            input.removingPercentEncoding ?? input
        }

        encoding?.setObject(base64EncodeFn, forKeyedSubscript: "base64Encode" as NSString)
        encoding?.setObject(base64DecodeFn, forKeyedSubscript: "base64Decode" as NSString)
        encoding?.setObject(urlEncodeFn, forKeyedSubscript: "urlEncode" as NSString)
        encoding?.setObject(urlDecodeFn, forKeyedSubscript: "urlDecode" as NSString)

        rockxy?.setObject(encoding, forKeyedSubscript: "encoding" as NSString)
    }

    private static func installStorage(
        on rockxy: JSValue?,
        context: JSContext,
        pluginID: String,
        defaults: UserDefaults
    ) {
        let storage = JSValue(newObjectIn: context)
        let prefix = RockxyIdentity.current.pluginStoragePrefix(pluginID: pluginID)

        let getFn: @convention(block) (String) -> Any? = { key in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("storage.get rejected invalid key '\(key)' for \(pluginID)")
                return nil
            }
            return defaults.object(forKey: prefix + key)
        }
        let setFn: @convention(block) (String, Any) -> Void = { key, value in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("storage.set rejected invalid key '\(key)' for \(pluginID)")
                return
            }
            defaults.set(value, forKey: prefix + key)
        }
        let deleteFn: @convention(block) (String) -> Void = { key in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("storage.delete rejected invalid key '\(key)' for \(pluginID)")
                return
            }
            defaults.removeObject(forKey: prefix + key)
        }

        storage?.setObject(getFn, forKeyedSubscript: "get" as NSString)
        storage?.setObject(setFn, forKeyedSubscript: "set" as NSString)
        storage?.setObject(deleteFn, forKeyedSubscript: "delete" as NSString)

        rockxy?.setObject(storage, forKeyedSubscript: "storage" as NSString)
    }

    private static func installEnv(
        on rockxy: JSValue?,
        context: JSContext,
        pluginID: String,
        defaults: UserDefaults
    ) {
        let env = JSValue(newObjectIn: context)
        let prefix = RockxyIdentity.current.pluginConfigPrefix(pluginID: pluginID)

        // env.get(key) — per-plugin configuration (always available, isolated by prefix).
        let getFn: @convention(block) (String) -> Any? = { key in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("env.get rejected invalid key '\(key)' for \(pluginID)")
                return nil
            }
            return defaults.object(forKey: prefix + key)
        }
        env?.setObject(getFn, forKeyedSubscript: "get" as NSString)

        // env.system(key) — host system environment variable. Gated on
        // `AppSettings.allowSystemEnvVars` (Advance menu toggle). When off, returns null.
        let systemFn: @convention(block) (String) -> Any? = { key in
            let allowed = AppSettingsStorage.load().allowSystemEnvVars
            guard allowed else {
                bridgeLogger.debug("env.system blocked for \(pluginID) — allowSystemEnvVars is off")
                return nil
            }
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("env.system rejected invalid key '\(key)' for \(pluginID)")
                return nil
            }
            return ProcessInfo.processInfo.environment[key]
        }
        env?.setObject(systemFn, forKeyedSubscript: "system" as NSString)

        rockxy?.setObject(env, forKeyedSubscript: "env" as NSString)
    }
}
