import Foundation
@testable import Rockxy
import Testing

struct JSONPathParserTests {
    @Test("Parses Jayway-style bookstore query")
    func parsesBookstoreQuery() throws {
        var parser = try JSONPathParser(source: "$.store.book[?(@.price < 10)].title")
        let expression = try parser.parse()

        #expect(expression.origin == .root)
        #expect(expression.segments.count == 4)
        #expect(expression.segments[0] == .child([.name("store")]))
        #expect(expression.segments[1] == .child([.name("book")]))
        #expect(expression.segments[3] == .child([.name("title")]))
    }

    @Test("Parses bracket unions, negative indexes, and slices")
    func parsesAdvancedSelectors() throws {
        var parser = try JSONPathParser(source: "$['store','expensive'].book[-1,0:3:2]")
        let expression = try parser.parse()

        #expect(expression.segments[0] == .child([.name("store"), .name("expensive")]))
        #expect(expression.segments[2] == .child([.index(-1), .slice(start: 0, end: 3, step: 2)]))
    }

    @Test("Parses deep scan and tail functions")
    func parsesDeepScanAndTailFunction() throws {
        var parser = try JSONPathParser(source: "$..price.sum()")
        let expression = try parser.parse()

        #expect(expression.segments == [.descendant([.name("price")])])
        #expect(expression.tailFunction == JSONPathFunctionCall(name: "sum", arguments: []))
    }

    @Test("Parses filter operators used by Jayway")
    func parsesFilterOperators() throws {
        let queries = [
            "$.items[?(@.id in [1,2])]",
            "$.items[?(@.id nin [3])]",
            "$.items[?(@.tags subsetof ['a','b'])]",
            "$.items[?(@.tags anyof ['b'])]",
            "$.items[?(@.tags noneof ['z'])]",
            "$.items[?(@.tags size 2)]",
            "$.items[?(@.tags empty false)]",
        ]

        for query in queries {
            var parser = try JSONPathParser(source: query)
            _ = try parser.parse()
        }
    }

    @Test("Reports invalid query diagnostics")
    func reportsInvalidQueries() {
        #expect(throws: JSONPathError.self) {
            var parser = try JSONPathParser(source: "store.book")
            _ = try parser.parse()
        }
        #expect(throws: JSONPathError.self) {
            var parser = try JSONPathParser(source: "$.store[")
            _ = try parser.parse()
        }
    }
}
