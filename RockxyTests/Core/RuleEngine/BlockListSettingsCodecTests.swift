import Foundation
@testable import Rockxy
import Testing

// MARK: - BlockListSettingsCodecTests

struct BlockListSettingsCodecTests {
    @Test("export includes only block rules")
    func exportIncludesOnlyBlockRules() throws {
        let block = TestFixtures.makeRule(name: "Block", action: .block(statusCode: 403))
        let throttle = TestFixtures.makeRule(name: "Throttle", action: .throttle(delayMs: 100))

        let data = try BlockListSettingsCodec.exportRules([block, throttle])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let blockRules = try #require(object["blockRules"] as? [[String: Any]])

        #expect(blockRules.count == 1)
        #expect(blockRules.first?["name"] as? String == "Block")
    }

    @Test("imports Proxyman-style flat patterns")
    func importProxymanFlatPatterns() throws {
        let data = Data(#"["*.example.com/ads/*","api.example.com"]"#.utf8)
        let rules = try BlockListSettingsCodec.importFromProxyman(data)

        #expect(rules.count == 2)
        #expect(rules.allSatisfy { rule in
            if case let .block(statusCode) = rule.action {
                return statusCode == 403
            }
            return false
        })
        #expect(rules.first?.matchCondition.urlPattern?.contains(".*") == true)
    }

    @Test("imports structured Proxyman entries with action and method")
    func importStructuredProxymanEntries() throws {
        let data = Data("""
        {
          "blockRules": [
            {"name":"Drop tracker","pattern":"^https://tracker\\\\.example/.*$","matchType":"regex","method":"GET","action":"Drop Connection","enabled":false}
          ]
        }
        """.utf8)

        let rules = try BlockListSettingsCodec.importFromProxyman(data)
        let rule = try #require(rules.first)

        #expect(rule.name == "Drop tracker")
        #expect(rule.isEnabled == false)
        #expect(rule.matchCondition.method == "GET")
        #expect(rule.matchCondition.urlPattern == #"^https://tracker\.example/.*$"#)
        if case let .block(statusCode) = rule.action {
            #expect(statusCode == 0)
        } else {
            Issue.record("Expected block action")
        }
    }

    @Test("imports Charles Proxy plist locations")
    func importCharlesProxyLocations() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>location</key>
            <array>
                <dict>
                    <key>host</key>
                    <string>api.example.com</string>
                    <key>path</key>
                    <string>/v1/ads</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let rules = try BlockListSettingsCodec.importFromCharlesProxy(Data(plist.utf8))
        let rule = try #require(rules.first)

        #expect(rule.name == "*api.example.com/v1/ads")
        #expect(rule.matchCondition.urlPattern?.contains("api\\.example\\.com") == true)
        if case let .block(statusCode) = rule.action {
            #expect(statusCode == 403)
        } else {
            Issue.record("Expected block action")
        }
    }

    @Test("invalid import throws")
    func invalidImportThrows() {
        #expect(throws: BlockListSettingsCodec.ImportError.self) {
            try BlockListSettingsCodec.importFromProxyman(Data("not json".utf8))
        }
        #expect(throws: BlockListSettingsCodec.ImportError.self) {
            try BlockListSettingsCodec.importFromCharlesProxy(Data("not plist".utf8))
        }
    }
}
