import Testing
import Foundation
import Alamofire
@testable import EasyNet

@Suite("NetworkServiceProvider URL Construction")
struct NetworkServiceProviderTests {

    @Test("Constructs correct URL from base and path")
    func asURLRequest_constructsCorrectURL() throws {
        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com",
            path: "users",
            method: .get,
            data: EmptyRequestContent()
        )
        let request = try provider.asURLRequest()
        #expect(request.url?.absoluteString.starts(with: "https://api.example.com/users") == true)
    }

    @Test("Handles trailing slashes in base URL and leading slashes in path")
    func asURLRequest_handlesSlashes() throws {
        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com/",
            path: "/users/",
            method: .get,
            data: EmptyRequestContent()
        )
        let request = try provider.asURLRequest()
        #expect(request.url?.absoluteString.starts(with: "https://api.example.com/users") == true)
    }

    @Test("GET requests use correct HTTP method")
    func asURLRequest_getMethod() throws {
        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com",
            path: "users",
            method: .get,
            data: EmptyRequestContent()
        )
        let request = try provider.asURLRequest()
        #expect(request.httpMethod == "GET")
    }

    @Test("POST requests use correct HTTP method")
    func asURLRequest_postMethod() throws {
        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com",
            path: "auth/login",
            method: .post,
            data: EmptyRequestContent()
        )
        let request = try provider.asURLRequest()
        #expect(request.httpMethod == "POST")
    }

    @Test("POST requests encode body as JSON")
    func asURLRequest_postEncodesBody() throws {
        struct LoginRequest: Encodable, Sendable {
            let email: String
            let password: String
        }

        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com",
            path: "auth/login",
            method: .post,
            data: LoginRequest(email: "test@test.com", password: "123456")
        )
        let request = try provider.asURLRequest()
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(body?["email"] as? String == "test@test.com")
        #expect(body?["password"] as? String == "123456")
    }

    @Test("Custom headers are applied")
    func asURLRequest_customHeaders() throws {
        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com",
            path: "users",
            method: .get,
            data: EmptyRequestContent(),
            headers: [HTTPHeader(name: "X-Custom", value: "test-value")]
        )
        let request = try provider.asURLRequest()
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "test-value")
    }

    @Test("Cache policy is set to reloadIgnoringCacheData")
    func asURLRequest_cachePolicy() throws {
        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com",
            path: "users",
            method: .get,
            data: EmptyRequestContent()
        )
        let request = try provider.asURLRequest()
        #expect(request.cachePolicy == .reloadIgnoringCacheData)
    }
}
