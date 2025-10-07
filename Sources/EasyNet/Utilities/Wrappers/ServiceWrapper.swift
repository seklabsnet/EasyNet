//
//  ServiceWrapper.swift
//  Swiftcn
//
//  Created by Salihcan Kahya on 17.04.2025.
//

import Alamofire

@propertyWrapper
public struct ServiceWrapper {
    let baseUrl: String
    let method: HTTPMethod
    let path: String
    
    public init(baseUrl: String, path: String, method: HTTPMethod = .post) {
        self.baseUrl = baseUrl
        self.method = method
        self.path = path
    }
 
    public var wrappedValue: URLRequestConvertible {
        NetworkServiceProvider(
            baseUrl: baseUrl,
            path: path,
            method: method,
            data: EmptyRequestContent()
        )
    }
}
