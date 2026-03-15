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
            let data = try JSONEncoder().encode(self)
            return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                as? [String: Any & Sendable] ?? [:]
        } catch {
            return [:]
        }
    }

    var jsonData: Data? {
        try? JSONEncoder().encode(self)
    }
}
