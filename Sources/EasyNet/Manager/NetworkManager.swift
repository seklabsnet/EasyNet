//
//  NetworkManager.swift
//  Swiftcn
//
//  Created by Salihcan Kahya on 17.04.2025.
//

import Foundation
import Alamofire

public struct NetworkManager: NetworkManagerProtocol {
    private let session: Session
    private let decoder = JSONDecoder()

    public init(session: Session) {
        self.session = session
    }

    public func execute<T: Decodable & Sendable>(
        urlRequest: URLRequestConvertible
    ) async throws -> T {
        let response = await session.request(urlRequest)
            .validate()
            .serializingDecodable(T.self, decoder: decoder)
            .response

        switch response.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw Self.mapError(error, responseData: response.data)
        }
    }

    public func executeCompletable(
        urlRequest: URLRequestConvertible
    ) async throws {
        let response = await session.request(urlRequest)
            .validate()
            .serializingData()
            .response

        if let error = response.error {
            throw Self.mapError(error, responseData: response.data)
        }
    }

    public func executeUpload<T: Decodable & Sendable>(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping @Sendable (MultipartFormData) -> Void
    ) async throws -> T {
        let response = await session.upload(
            multipartFormData: multipartFormData,
            with: urlRequest
        )
        .validate()
        .serializingDecodable(T.self, decoder: decoder)
        .response

        switch response.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw Self.mapError(error, responseData: response.data)
        }
    }

    public func executeUploadCompletable(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping @Sendable (MultipartFormData) -> Void
    ) async throws {
        let response = await session.upload(
            multipartFormData: multipartFormData,
            with: urlRequest
        )
        .validate()
        .serializingData()
        .response

        if let error = response.error {
            throw Self.mapError(error, responseData: response.data)
        }
    }

    static func mapError(_ error: AFError, responseData: Data?) -> NetworkError {
        switch error {
        case .responseValidationFailed(let reason):
            if case .unacceptableStatusCode(let code) = reason, code == 401 {
                return .unauthorized(responseData)
            }
            return .requestFailed(error, responseData)

        case .responseSerializationFailed:
            return .decodingFailed(error, responseData)

        default:
            return .requestFailed(error, responseData)
        }
    }
}
