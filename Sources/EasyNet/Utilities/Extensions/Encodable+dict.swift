//
//  Encodable+dict.swift
//  Swiftcn
//
//  Created by Salihcan Kahya on 17.04.2025.
//

import Foundation
import Alamofire

extension Encodable {
    func asDictionary() -> Parameters {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
 
            return try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any & Sendable] ?? [:]
        } catch {
            return [:]
        }
    }
 
    var jsonData: Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
 
    var jsonString: String? {
        guard let data = self.jsonData else { return nil }
        return String(data: data, encoding: .utf8)
    }
 
    func toJson() -> Data? {
        return try? JSONEncoder().encode(self)
    }
}
