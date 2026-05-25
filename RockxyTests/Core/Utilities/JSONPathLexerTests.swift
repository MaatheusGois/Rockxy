import Foundation
@testable import Rockxy
import Testing

struct JSONPathLexerTests {
    @Test("Tokenizes root, child, wildcard, deep scan, and bracket selectors")
    func tokenizesPathSyntax() throws {
        let tokens = try JSONPathLexer(source: "$.store.book[*]..author").tokenize()

        #expect(tokens == [
            .root,
            .dot,
            .identifier("store"),
            .dot,
            .identifier("book"),
            .leftBracket,
            .star,
            .rightBracket,
            .deepScan,
            .identifier("author"),
            .eof,
        ])
    }

    @Test("Tokenizes filters with regex and logical operators")
    func tokenizesFilters() throws {
        let tokens = try JSONPathLexer(source: "$..book[?(@.author =~ /.*REES/i && @.price < 10)]").tokenize()

        #expect(tokens.contains(.regexMatch))
        #expect(tokens.contains(.regex(pattern: ".*REES", options: [.caseInsensitive])))
        #expect(tokens.contains(.and))
        #expect(tokens.contains(.less))
        #expect(tokens.contains(.number("10")))
    }

    @Test("Respects query and regex limits")
    func respectsLimits() {
        let limits = JSONPathEvaluationLimits(
            maxQueryLength: 4,
            maxLiveFilterBodyBytes: 10,
            maxVisitedNodes: 10,
            maxResultNodes: 10,
            maxTreeDepth: 10,
            maxASTDepth: 10,
            maxRegexPatternLength: 3
        )

        #expect(throws: JSONPathError.self) {
            _ = try JSONPathLexer(source: "$.long", limits: limits).tokenize()
        }
        #expect(throws: JSONPathError.self) {
            _ = try JSONPathLexer(source: "$[?(@.name =~ /abcd/)]", limits: limits).tokenize()
        }
    }

    @Test("Rejects invalid operators")
    func rejectsInvalidOperators() {
        #expect(throws: JSONPathError.self) {
            _ = try JSONPathLexer(source: "$[?(@.price = 10)]").tokenize()
        }
    }
}
