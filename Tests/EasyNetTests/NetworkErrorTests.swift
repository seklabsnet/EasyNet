import Testing
import Foundation
@testable import EasyNet

@Suite("NetworkError")
struct NetworkErrorTests {

    @Test("responseData returns data for requestFailed")
    func responseData_requestFailed() {
        let data = "error".data(using: .utf8)
        let error = NetworkError.requestFailed(NSError(domain: "", code: 0), data)
        #expect(error.responseData == data)
    }

    @Test("responseData returns data for decodingFailed")
    func responseData_decodingFailed() {
        let data = "bad json".data(using: .utf8)
        let error = NetworkError.decodingFailed(NSError(domain: "", code: 0), data)
        #expect(error.responseData == data)
    }

    @Test("responseData returns data for serverError")
    func responseData_serverError() {
        let data = "server error".data(using: .utf8)
        let error = NetworkError.serverError("500", data)
        #expect(error.responseData == data)
    }

    @Test("responseData returns data for unauthorized")
    func responseData_unauthorized() {
        let data = "unauthorized".data(using: .utf8)
        let error = NetworkError.unauthorized(data)
        #expect(error.responseData == data)
    }

    @Test("responseData returns nil for invalidURL")
    func responseData_invalidURL() {
        #expect(NetworkError.invalidURL.responseData == nil)
    }

    @Test("responseData returns nil for noData")
    func responseData_noData() {
        #expect(NetworkError.noData.responseData == nil)
    }

    @Test("responseData returns nil for unknown")
    func responseData_unknown() {
        #expect(NetworkError.unknown.responseData == nil)
    }

    @Test("LocalizedError errorDescription works through Error protocol")
    func localizedDescription_throughErrorProtocol() {
        let error: Error = NetworkError.unauthorized(nil)
        #expect(error.localizedDescription == "Unauthorized access")
    }

    @Test("errorDescription for invalidURL")
    func errorDescription_invalidURL() {
        #expect(NetworkError.invalidURL.errorDescription == "Invalid URL")
    }

    @Test("errorDescription for noData")
    func errorDescription_noData() {
        #expect(NetworkError.noData.errorDescription == "No data received from server")
    }

    @Test("errorDescription for unknown")
    func errorDescription_unknown() {
        #expect(NetworkError.unknown.errorDescription == "An unknown error occurred")
    }
}
