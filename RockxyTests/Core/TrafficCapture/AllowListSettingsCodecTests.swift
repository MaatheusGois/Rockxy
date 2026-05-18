import Foundation
@testable import Rockxy
import Testing

// MARK: - AllowListSettingsCodecTests

@MainActor
struct AllowListSettingsCodecTests {
    // MARK: - Proxyman / JSON

    @Test("imports flat JSON array as wildcard allow rules")
    func importProxymanFlatArray() throws {
        let json = """
        ["*.example.com", "api.stripe.com", "API.STRIPE.com", " "]
        """

        let rules = try AllowListSettingsCodec.importFromProxyman(Data(json.utf8))

        #expect(rules.count == 2)
        #expect(rules[0].rawPattern == "*.example.com")
        #expect(rules[0].matchType == .wildcard)
        #expect(rules[0].method == nil)
        #expect(rules[1].rawPattern == "api.stripe.com")
    }

    @Test("imports structured JSON entries with method, enabled state, and names")
    func importProxymanStructuredEntries() throws {
        let json = """
        {
          "allowRules": [
            {
              "name": "Stripe charges",
              "host": "api.stripe.com",
              "path": "/v1/charges",
              "method": "post",
              "enabled": false
            },
            {
              "name": "GitHub regex",
              "pattern": "^https://api\\\\.github\\\\.com/.*$",
              "matchType": "regex",
              "method": "ANY"
            }
          ]
        }
        """

        let rules = try AllowListSettingsCodec.importFromProxyman(Data(json.utf8))

        #expect(rules.count == 2)
        #expect(rules[0].name == "Stripe charges")
        #expect(rules[0].rawPattern == "*api.stripe.com/v1/charges")
        #expect(rules[0].method == "POST")
        #expect(!rules[0].isEnabled)
        #expect(rules[1].matchType == .regex)
        #expect(rules[1].includeSubpaths == false)
        #expect(rules[1].method == nil)
    }

    @Test("throws for invalid JSON")
    func importProxymanInvalidJSON() {
        #expect(throws: AllowListSettingsCodec.ImportError.self) {
            try AllowListSettingsCodec.importFromProxyman(Data("bad".utf8))
        }
    }

    @Test("throws when JSON contains no usable rules")
    func importProxymanNoRules() {
        let json = """
        {"allowRules":[{"host":"   "}]}
        """

        #expect(throws: AllowListSettingsCodec.ImportError.self) {
            try AllowListSettingsCodec.importFromProxyman(Data(json.utf8))
        }
    }

    @Test("throws when imported regex is invalid")
    func importProxymanInvalidRegex() {
        let json = """
        {"allowRules":[{"pattern":"^[unclosed","matchType":"regex"}]}
        """

        #expect(throws: AllowListSettingsCodec.ImportError.self) {
            try AllowListSettingsCodec.importFromProxyman(Data(json.utf8))
        }
    }

    // MARK: - Charles Proxy / Plist

    @Test("imports Charles plist locations")
    func importCharlesLocations() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>location</key>
            <array>
                <dict>
                    <key>host</key>
                    <string>api.github.com</string>
                    <key>path</key>
                    <string>/repos</string>
                    <key>method</key>
                    <string>GET</string>
                </dict>
                <dict>
                    <key>host</key>
                    <string>*.example.com</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let rules = try AllowListSettingsCodec.importFromCharlesProxy(Data(plist.utf8))

        #expect(rules.count == 2)
        #expect(rules[0].rawPattern == "*api.github.com/repos")
        #expect(rules[0].method == "GET")
        #expect(rules[1].rawPattern == "**.example.com/")
    }

    @Test("throws for invalid Charles plist")
    func importCharlesInvalidFormat() {
        #expect(throws: AllowListSettingsCodec.ImportError.self) {
            try AllowListSettingsCodec.importFromCharlesProxy(Data("not plist".utf8))
        }
    }
}
