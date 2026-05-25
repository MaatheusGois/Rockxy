import Foundation
@testable import Rockxy
import Testing

struct JSONTreeFilteringTests {
    @Test("Filtered JSON tree retains ancestors for matched descendants")
    func retainsAncestorsForMatchedDescendants() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "posts": [
                [
                    "makers": ["a", "b", "c"],
                    "user": ["name": "First"],
                ],
                [
                    "makers": ["d", "e", "target-maker"],
                    "user": ["name": "Second"],
                ],
            ],
        ])
        let document = try JSONPathDocument(data: data)
        let result = try JSONPathEvaluator(document: document).keyPath("posts[1].makers[2]")

        #expect(result.matches.map(\.path) == ["$['posts'][1]['makers'][2]"])
        #expect(result.includedPaths.contains("$"))
        #expect(result.includedPaths.contains("$['posts']"))
        #expect(result.includedPaths.contains("$['posts'][1]"))
        #expect(result.includedPaths.contains("$['posts'][1]['makers']"))
        #expect(result.includedPaths.contains("$['posts'][1]['makers'][2]"))
        #expect(!result.includedPaths.contains("$['posts'][0]"))
    }
}
