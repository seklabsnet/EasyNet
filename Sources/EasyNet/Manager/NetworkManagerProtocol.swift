//
//  NetworkManagerProtocol.swift
//  Swiftcn
//
//  Created by Salihcan Kahya on 17.04.2025.
//

import Alamofire

public protocol NetworkManagerProtocol: Sendable {
    func execute<T: Decodable & Sendable>(
        urlRequest: URLRequestConvertible
    ) async throws -> T

    func executeCompletable(
        urlRequest: URLRequestConvertible
    ) async throws

    func executeUpload<T: Decodable & Sendable>(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping @Sendable (MultipartFormData) -> Void
    ) async throws -> T

    func executeUploadCompletable(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping @Sendable (MultipartFormData) -> Void
    ) async throws
}
