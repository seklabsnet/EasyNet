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
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                urlRequest
            )
            .validate()
            .responseDecodable(of: T.self, decoder: decoder) { response in
                switch response.result {
                case .success(let globalResponse):
                    continuation.resume(returning: globalResponse)
                case .failure(let error):
                    if let afError = error.asAFError {
                        switch afError {
                        case .responseValidationFailed(let reason):
                            if case .unacceptableStatusCode(let code) = reason, code == 401 {
                                continuation.resume(throwing: NetworkError.unauthorized(response.data))
                            } else {
                                continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                            }
                        case .responseSerializationFailed:
                            continuation.resume(throwing: NetworkError.decodingFailed(error, response.data))
                        default:
                            continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                        }
                    } else {
                        continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                    }
                }
            }
        }
    }
    
    public func executeCompletable(
        urlRequest: URLRequestConvertible
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                urlRequest
            )
            .validate()
            .response { response in
                switch response.result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    if let afError = error.asAFError {
                        switch afError {
                        case .responseValidationFailed(let reason):
                            if case .unacceptableStatusCode(let code) = reason, code == 401 {
                                continuation.resume(throwing: NetworkError.unauthorized(response.data))
                            } else {
                                continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                            }
                        default:
                            continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                        }
                    } else {
                        continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                    }
                }
            }
        }
    }
    
    public func executeUpload<T: Decodable & Sendable>(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping (MultipartFormData) -> Void
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            session.upload(
                multipartFormData: multipartFormData,
                with: urlRequest
            )
            .validate()
            .responseDecodable(of: T.self, decoder: decoder) { response in
                switch response.result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    if let afError = error.asAFError {
                        switch afError {
                        case .responseValidationFailed(let reason):
                            if case .unacceptableStatusCode(let code) = reason, code == 401 {
                                continuation.resume(throwing: NetworkError.unauthorized(response.data))
                            } else {
                                continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                            }
                        default:
                            continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                        }
                    } else {
                        continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                    }
                }
            }
        }
    }
    
    public func executeUploadCompletable(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping (MultipartFormData) -> Void
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            session.upload(
                multipartFormData: multipartFormData,
                with: urlRequest
            )
            .validate()
            .response { response in
                switch response.result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    if let afError = error.asAFError {
                        switch afError {
                        case .responseValidationFailed(let reason):
                            if case .unacceptableStatusCode(let code) = reason, code == 401 {
                                continuation.resume(throwing: NetworkError.unauthorized(response.data))
                            } else {
                                continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                            }
                        default:
                            continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                        }
                    } else {
                        continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
                    }
                }
            }
        }
    }
}

