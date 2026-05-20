import Foundation

enum TestEndpoints {
    static let httpbinHTTP = URL(string: "http://httpbin.org")!
    static let httpbinHTTPS = URL(string: "https://httpbin.org")!
    static let httpbingoHTTPS = URL(string: "https://httpbingo.org")!
    static let postmanEchoHTTPS = URL(string: "https://postman-echo.com")!
    static let localFlutterProfile = URL(string: "http://127.0.0.1:43210/rockxy-demo/profile")!

    static func httpbinHTTP(_ path: String) -> URL {
        httpbinHTTP.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    static func httpbinHTTPS(_ path: String) -> URL {
        httpbinHTTPS.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    static func httpbingoHTTPS(_ path: String) -> URL {
        httpbingoHTTPS.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
