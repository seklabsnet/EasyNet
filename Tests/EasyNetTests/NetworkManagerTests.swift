import Testing
import Foundation
import Alamofire
@testable import EasyNet

@Suite("NetworkManager Error Mapping")
struct NetworkManagerTests {

    @Test("401 status code maps to unauthorized")
    func mapError_401_returnsUnauthorized() {
        let error = AFError.responseValidationFailed(
            reason: .unacceptableStatusCode(code: 401)
        )
        let testData = "unauthorized".data(using: .utf8)
        let result = NetworkManager.mapError(error, responseData: testData)

        guard case .unauthorized(let data) = result else {
            Issue.record("Expected .unauthorized, got \(result)")
            return
        }
        #expect(data == testData)
    }

    @Test("Serialization failure maps to decodingFailed")
    func mapError_serializationFailed_returnsDecodingFailed() {
        let error = AFError.responseSerializationFailed(
            reason: .inputDataNilOrZeroLength
        )
        let result = NetworkManager.mapError(error, responseData: nil)

        guard case .decodingFailed = result else {
            Issue.record("Expected .decodingFailed, got \(result)")
            return
        }
    }

    @Test("Other validation failures map to requestFailed")
    func mapError_otherValidation_returnsRequestFailed() {
        let error = AFError.responseValidationFailed(
            reason: .unacceptableStatusCode(code: 500)
        )
        let result = NetworkManager.mapError(error, responseData: nil)

        guard case .requestFailed = result else {
            Issue.record("Expected .requestFailed, got \(result)")
            return
        }
    }

    @Test("Explicitly cancelled maps to cancelled")
    func mapError_cancelled_returnsCancelled() {
        let error = AFError.explicitlyCancelled
        let result = NetworkManager.mapError(error, responseData: nil)

        guard case .cancelled = result else {
            Issue.record("Expected .cancelled, got \(result)")
            return
        }
    }

    @Test("Not connected to internet maps to noInternet")
    func mapError_noInternet_returnsNoInternet() {
        let urlError = URLError(.notConnectedToInternet)
        let error = AFError.sessionTaskFailed(error: urlError)
        let result = NetworkManager.mapError(error, responseData: nil)

        guard case .noInternet = result else {
            Issue.record("Expected .noInternet, got \(result)")
            return
        }
    }

    @Test("Other session task errors map to requestFailed")
    func mapError_otherSessionError_returnsRequestFailed() {
        let urlError = URLError(.timedOut)
        let error = AFError.sessionTaskFailed(error: urlError)
        let result = NetworkManager.mapError(error, responseData: nil)

        guard case .requestFailed = result else {
            Issue.record("Expected .requestFailed, got \(result)")
            return
        }
    }

    @Test("Response data is preserved through error mapping")
    func mapError_preservesResponseData() {
        let testData = "{\"error\": \"test\"}".data(using: .utf8)
        let error = AFError.responseValidationFailed(
            reason: .unacceptableStatusCode(code: 403)
        )
        let result = NetworkManager.mapError(error, responseData: testData)

        guard case .requestFailed(_, let data) = result else {
            Issue.record("Expected .requestFailed, got \(result)")
            return
        }
        #expect(data == testData)
    }
}
