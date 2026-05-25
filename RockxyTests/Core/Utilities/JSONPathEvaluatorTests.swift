import Foundation
@testable import Rockxy
import Testing

struct JSONPathEvaluatorTests {
    @Test("Evaluates Jayway bookstore examples")
    func evaluatesBookstoreExamples() throws {
        let evaluator = try JSONPathEvaluator(document: bookstoreDocument())

        #expect(try evaluator.evaluate("$.store.book[*].author").matches.map(\.scalarDescription) == [
            "Nigel Rees",
            "Evelyn Waugh",
            "Herman Melville",
            "J. R. R. Tolkien",
        ])
        #expect(try evaluator.evaluate("$..author").matches.map(\.scalarDescription).contains("Nigel Rees"))
        #expect(try evaluator.evaluate("$.store.book[?(@.price < 10)].title").matches.map(\.scalarDescription) == [
            "Sayings of the Century",
            "Moby Dick",
        ])
        #expect(try evaluator.evaluate("$.store.book[-1].title").matches.first?.scalarDescription == "The Lord of the Rings")
        #expect(try evaluator.evaluate("$.store.book[0:2].title").matches.map(\.scalarDescription) == [
            "Sayings of the Century",
            "Sword of Honour",
        ])
    }

    @Test("Supports key paths and wildcard user-name projections")
    func supportsKeyPathAndProjection() throws {
        let evaluator = try JSONPathEvaluator(document: postsDocument())

        #expect(try evaluator.keyPath("posts[1].makers[2]").matches.first?.scalarDescription == "third-maker")
        #expect(try evaluator.evaluate("$.posts[*].user.name").matches.map(\.scalarDescription) == [
            "Danni Friedland",
            "Chris Messina",
        ])
    }

    @Test("Searches all keys and all values with literal and regex queries")
    func searchesKeysAndValues() throws {
        let evaluator = try JSONPathEvaluator(document: postsDocument())

        let keyMatches = try evaluator.search("username", mode: .allKeys)
        let valueMatches = try evaluator.search("/friedland/", mode: .allValues)

        #expect(keyMatches.matches.count == 2)
        #expect(valueMatches.matches.map(\.scalarDescription).contains("Danni Friedland"))
        #expect(valueMatches.matches.map(\.scalarDescription).contains("danni_friedland"))
    }

    @Test("Supports regex, set, size, empty, null, and false filter behavior")
    func supportsAdvancedFilters() throws {
        let evaluator = try JSONPathEvaluator(document: filtersDocument())

        #expect(try evaluator.evaluate("$.items[?(@.name =~ /alpha/i)].id").matches.map(\.scalarDescription) == ["1"])
        #expect(try evaluator.evaluate("$.items[?(@.id in [1,3])].name").matches.map(\.scalarDescription) == ["Alpha", "Gamma"])
        #expect(try evaluator.evaluate("$.items[?(@.tags subsetof ['a','b'])].name").matches.map(\.scalarDescription) == ["Alpha"])
        #expect(try evaluator.evaluate("$.items[?(@.tags anyof ['c'])].name").matches.map(\.scalarDescription) == ["Beta"])
        #expect(try evaluator.evaluate("$.items[?(@.tags noneof ['z'])].name").matches.count == 3)
        #expect(try evaluator.evaluate("$.items[?(@.tags size 0)].name").matches.map(\.scalarDescription) == ["Gamma"])
        #expect(try evaluator.evaluate("$.items[?(@.tags empty true)].name").matches.map(\.scalarDescription) == ["Gamma"])
        #expect(try evaluator.evaluate("$.items[?(@.nullable)].name").matches.map(\.scalarDescription) == ["Alpha"])
        #expect(try evaluator.evaluate("$.items[?(@.enabled)].name").matches.map(\.scalarDescription) == ["Alpha", "Beta"])
    }

    @Test("Uses type-strict comparisons and reports missing fields as no matches")
    func usesStrictComparisonAndMissingFields() throws {
        let evaluator = try JSONPathEvaluator(document: filtersDocument())

        #expect(try evaluator.evaluate("$.items[?(@.id == '1')].name").matches.isEmpty)
        #expect(try evaluator.evaluate("$.items[?(@.missing == true)].name").matches.isEmpty)
    }

    @Test("Supports tail functions and result truncation")
    func supportsFunctionsAndTruncation() throws {
        let document = try bookstoreDocument()
        let evaluator = JSONPathEvaluator(document: document)
        let limited = JSONPathEvaluator(
            document: document,
            limits: JSONPathEvaluationLimits(
                maxQueryLength: 2_048,
                maxLiveFilterBodyBytes: 10_000,
                maxVisitedNodes: 100,
                maxResultNodes: 2,
                maxTreeDepth: 20,
                maxASTDepth: 20,
                maxRegexPatternLength: 128
            )
        )

        #expect(try evaluator.evaluate("$.store.book[*].price.sum()").matches.first?.scalarDescription == "53.92")
        #expect(try evaluator.evaluate("$.store.book[*].price.length()").matches.first?.scalarDescription == "4")

        let truncated = try limited.evaluate("$.store.book[*].title")
        #expect(truncated.matches.count == 2)
        #expect(truncated.isTruncated)
    }

    @Test("Reports invalid query diagnostics")
    func reportsInvalidQueries() throws {
        let evaluator = try JSONPathEvaluator(document: bookstoreDocument())

        #expect(throws: JSONPathError.self) {
            _ = try evaluator.evaluate("$.store.book[")
        }
    }
}

private func bookstoreDocument() throws -> JSONPathDocument {
    try document([
        "store": [
            "book": [
                [
                    "category": "reference",
                    "author": "Nigel Rees",
                    "title": "Sayings of the Century",
                    "price": 8.95,
                ],
                [
                    "category": "fiction",
                    "author": "Evelyn Waugh",
                    "title": "Sword of Honour",
                    "price": 12.99,
                ],
                [
                    "category": "fiction",
                    "author": "Herman Melville",
                    "title": "Moby Dick",
                    "isbn": "0-553-21311-3",
                    "price": 8.99,
                ],
                [
                    "category": "fiction",
                    "author": "J. R. R. Tolkien",
                    "title": "The Lord of the Rings",
                    "isbn": "0-395-19395-8",
                    "price": 22.99,
                ],
            ],
            "bicycle": [
                "color": "red",
                "price": 19.95,
            ],
        ],
        "expensive": 10,
    ])
}

private func postsDocument() throws -> JSONPathDocument {
    try document([
        "posts": [
            [
                "makers": ["first-maker"],
                "user": [
                    "name": "Danni Friedland",
                    "username": "danni_friedland",
                ],
            ],
            [
                "makers": ["first-maker", "second-maker", "third-maker"],
                "user": [
                    "name": "Chris Messina",
                    "username": "chrismessina",
                ],
            ],
        ],
    ])
}

private func filtersDocument() throws -> JSONPathDocument {
    try document([
        "items": [
            [
                "id": 1,
                "name": "Alpha",
                "tags": ["a", "b"],
                "nullable": NSNull(),
                "enabled": false,
            ],
            [
                "id": 2,
                "name": "Beta",
                "tags": ["b", "c"],
                "enabled": true,
            ],
            [
                "id": 3,
                "name": "Gamma",
                "tags": [],
            ],
        ],
    ])
}

private func document(_ object: [String: Any]) throws -> JSONPathDocument {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try JSONPathDocument(data: data)
}
