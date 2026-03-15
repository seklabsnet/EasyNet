//
//  NetworkError.swift
//  Swiftcn
//
//  Created by Salihcan Kahya on 17.04.2025.
//

import Foundation

public enum NetworkError: Error {
    case invalidURL
    case requestFailed(Error, Data? = nil)
    case decodingFailed(Error, Data? = nil)
    case serverError(String, Data? = nil)
    case noData
    case unauthorized(Data? = nil)
    case unknown

    public var responseData: Data? {
        switch self {
        case .requestFailed(_, let data):
            return data
        case .decodingFailed(_, let data):
            return data
        case .serverError(_, let data):
            return data
        case .unauthorized(let data):
            return data
        default:
            return nil
        }
    }
}

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed(let error, _):
            return "Request failed: \(error.localizedDescription)"
        case .decodingFailed(let error, _):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let message, _):
            return "Server error: \(message)"
        case .noData:
            return "No data received from server"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
