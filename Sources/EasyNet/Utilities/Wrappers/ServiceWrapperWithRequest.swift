//
//  ServiceWrapperWithRequest.swift
//  Swiftcn
//
//  Created by Salihcan Kahya on 17.04.2025.
//

import Alamofire

@propertyWrapper
public struct ServiceWrapperWithRequest<T: Encodable & Sendable> {
    let baseUrl: String
    let method: HTTPMethod
    let path: String
    let data: T
    
    public init(baseUrl: String,path: String, data: T, method: HTTPMethod = .post) {
        self.baseUrl = baseUrl
        self.method = method
        self.path = path
        self.data = data
    }
 
    public var wrappedValue: URLRequestConvertible {
        NetworkServiceProvider(
            baseUrl: baseUrl,
            path: path,
            method: method,
            data: data
        )
    }
}
