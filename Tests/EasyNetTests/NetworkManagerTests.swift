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

    @Test("Unknown AFError maps to requestFailed")
    func mapError_unknownError_returnsRequestFailed() {
        let error = AFError.explicitlyCancelled
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
