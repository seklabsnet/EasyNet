//
//  NetworkServiceProvider.swift
//  Swiftcn
//
//  Created by Salihcan Kahya on 16.04.2025.
//

import Foundation
import Alamofire

public final class NetworkServiceProvider<R: Encodable & Sendable>: URLRequestConvertible {
    private let baseUrl: String
    private let path: String
    private let method: HTTPMethod
    private let data: R
    private let requestHeaders: [HTTPHeader]
    
    public init(
        baseUrl: String,
        path: String,
        method: HTTPMethod = .post,
        data: R,
        headers: [HTTPHeader] = []
    ) {
        self.baseUrl = baseUrl
        self.path = path
        self.method = method
        self.data = data
        self.requestHeaders = headers
    }
    
    public func asURLRequest() throws -> URLRequest {
        // Properly construct URL by concatenating baseUrl and path
        let cleanBaseUrl = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullUrl = "\(cleanBaseUrl)/\(cleanPath)"
        
        let url = try fullUrl.asURL()
 
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.headers = headers
        request.cachePolicy = .reloadIgnoringCacheData
 
        return try encoding.encode(request, with: params)
    }
    
    private var encoding: ParameterEncoding {
        switch method {
        case .post, .patch, .put:
            return JSONEncoding.default
        case .get:
            return URLEncoding.queryString
        default:
            return URLEncoding.queryString
        }
    }
 
    private var params: Parameters? {
        return data.asDictionary()
    }
 
    private var headers: HTTPHeaders {
        var httpHeaders = HTTPHeaders()
        requestHeaders.forEach { header in
            httpHeaders.add(header)
        }
        return httpHeaders
    }
}
