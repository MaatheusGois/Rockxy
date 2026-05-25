import Foundation

// MARK: - JSONPathToken

enum JSONPathToken: Equatable, Sendable {
    case root
    case current
    case dot
    case deepScan
    case star
    case leftBracket
    case rightBracket
    case leftParen
    case rightParen
    case comma
    case colon
    case question
    case bang
    case and
    case or
    case equal
    case notEqual
    case less
    case lessOrEqual
    case greater
    case greaterOrEqual
    case regexMatch
    case identifier(String)
    case string(String)
    case number(String)
    case regex(pattern: String, options: NSRegularExpression.Options)
    case bool(Bool)
    case null
    case eof
}

// MARK: - JSONPathLexer

struct JSONPathLexer {
    let source: String
    let limits: JSONPathEvaluationLimits

    init(source: String, limits: JSONPathEvaluationLimits = .default) {
        self.source = source
        self.limits = limits
    }

    func tokenize() throws -> [JSONPathToken] {
        guard source.count <= limits.maxQueryLength else {
            throw JSONPathError.limitExceeded(String(localized: "Query is too long."))
        }

        var scanner = JSONPathScanner(source)
        var tokens: [JSONPathToken] = []

        while let char = scanner.peek() {
            if char.isWhitespace {
                scanner.advance()
                continue
            }

            switch char {
            case "$":
                scanner.advance()
                tokens.append(.root)
            case "@":
                scanner.advance()
                tokens.append(.current)
            case ".":
                scanner.advance()
                if scanner.peek() == "." {
                    scanner.advance()
                    tokens.append(.deepScan)
                } else {
                    tokens.append(.dot)
                }
            case "*":
                scanner.advance()
                tokens.append(.star)
            case "[":
                scanner.advance()
                tokens.append(.leftBracket)
            case "]":
                scanner.advance()
                tokens.append(.rightBracket)
            case "(":
                scanner.advance()
                tokens.append(.leftParen)
            case ")":
                scanner.advance()
                tokens.append(.rightParen)
            case ",":
                scanner.advance()
                tokens.append(.comma)
            case ":":
                scanner.advance()
                tokens.append(.colon)
            case "?":
                scanner.advance()
                tokens.append(.question)
            case "!":
                scanner.advance()
                if scanner.peek() == "=" {
                    scanner.advance()
                    tokens.append(.notEqual)
                } else {
                    tokens.append(.bang)
                }
            case "=":
                scanner.advance()
                if scanner.peek() == "=" {
                    scanner.advance()
                    tokens.append(.equal)
                } else if scanner.peek() == "~" {
                    scanner.advance()
                    tokens.append(.regexMatch)
                } else {
                    throw JSONPathError.invalidQuery(String(localized: "Unexpected '='."))
                }
            case "<":
                scanner.advance()
                if scanner.peek() == "=" {
                    scanner.advance()
                    tokens.append(.lessOrEqual)
                } else {
                    tokens.append(.less)
                }
            case ">":
                scanner.advance()
                if scanner.peek() == "=" {
                    scanner.advance()
                    tokens.append(.greaterOrEqual)
                } else {
                    tokens.append(.greater)
                }
            case "&":
                scanner.advance()
                guard scanner.peek() == "&" else {
                    throw JSONPathError.invalidQuery(String(localized: "Expected &&."))
                }
                scanner.advance()
                tokens.append(.and)
            case "|":
                scanner.advance()
                guard scanner.peek() == "|" else {
                    throw JSONPathError.invalidQuery(String(localized: "Expected ||."))
                }
                scanner.advance()
                tokens.append(.or)
            case "\"", "'":
                tokens.append(.string(try scanner.readString()))
            case "/":
                let regex = try scanner.readRegex(maxPatternLength: limits.maxRegexPatternLength)
                tokens.append(.regex(pattern: regex.pattern, options: regex.options))
            default:
                if char == "-" || char.isNumber {
                    tokens.append(.number(scanner.readNumber()))
                } else if isIdentifierStart(char) {
                    let identifier = scanner.readIdentifier()
                    tokens.append(Self.token(forIdentifier: identifier))
                } else {
                    throw JSONPathError.invalidQuery(String(localized: "Unexpected character '\(String(char))'."))
                }
            }
        }

        tokens.append(.eof)
        return tokens
    }

    private static func token(forIdentifier identifier: String) -> JSONPathToken {
        switch identifier {
        case "true": .bool(true)
        case "false": .bool(false)
        case "null": .null
        case "in",
             "nin",
             "subsetof",
             "anyof",
             "noneof",
             "size",
             "empty":
            .identifier(identifier)
        default:
            .identifier(identifier)
        }
    }

    private func isIdentifierStart(_ char: Character) -> Bool {
        char == "_" || char.isLetter
    }
}

// MARK: - JSONPathScanner

private struct JSONPathScanner {
    private let characters: [Character]
    private var index: Int = 0

    init(_ source: String) {
        characters = Array(source)
    }

    func peek(offset: Int = 0) -> Character? {
        let target = index + offset
        guard target < characters.count else {
            return nil
        }
        return characters[target]
    }

    mutating func advance() {
        index += 1
    }

    mutating func readIdentifier() -> String {
        var result = ""
        while let char = peek(), char == "_" || char == "-" || char.isLetter || char.isNumber {
            result.append(char)
            advance()
        }
        return result
    }

    mutating func readNumber() -> String {
        var result = ""
        if peek() == "-" {
            result.append("-")
            advance()
        }
        while let char = peek(), char.isNumber {
            result.append(char)
            advance()
        }
        if peek() == "." {
            result.append(".")
            advance()
            while let char = peek(), char.isNumber {
                result.append(char)
                advance()
            }
        }
        if let char = peek(), char == "e" || char == "E" {
            result.append(char)
            advance()
            if let sign = peek(), sign == "+" || sign == "-" {
                result.append(sign)
                advance()
            }
            while let char = peek(), char.isNumber {
                result.append(char)
                advance()
            }
        }
        return result
    }

    mutating func readString() throws -> String {
        guard let quote = peek() else {
            throw JSONPathError.invalidQuery(String(localized: "Expected string."))
        }
        advance()
        var result = ""
        while let char = peek() {
            advance()
            if char == quote {
                return result
            }
            if char == "\\" {
                guard let escaped = peek() else {
                    throw JSONPathError.invalidQuery(String(localized: "Unterminated escape sequence."))
                }
                advance()
                switch escaped {
                case "\"": result.append("\"")
                case "'": result.append("'")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{0008}")
                case "f": result.append("\u{000C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default: result.append(escaped)
                }
            } else {
                result.append(char)
            }
        }
        throw JSONPathError.invalidQuery(String(localized: "Unterminated string."))
    }

    mutating func readRegex(maxPatternLength: Int) throws -> (pattern: String, options: NSRegularExpression.Options) {
        advance()
        var pattern = ""
        var escaped = false
        while let char = peek() {
            advance()
            if escaped {
                pattern.append("\\")
                pattern.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "/" {
                var options: NSRegularExpression.Options = []
                while let flag = peek(), flag.isLetter {
                    if flag == "i" {
                        options.insert(.caseInsensitive)
                    }
                    advance()
                }
                guard pattern.count <= maxPatternLength else {
                    throw JSONPathError.limitExceeded(String(localized: "Regex pattern is too long."))
                }
                return (pattern, options)
            } else {
                pattern.append(char)
            }
        }
        throw JSONPathError.invalidQuery(String(localized: "Unterminated regex."))
    }
}
