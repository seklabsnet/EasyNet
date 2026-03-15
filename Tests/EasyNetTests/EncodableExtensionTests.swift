import Testing
import Foundation
@testable import EasyNet

@Suite("Encodable Extensions")
struct EncodableExtensionTests {

    struct TestModel: Encodable, Sendable {
        let name: String
        let age: Int
    }

    struct NestedModel: Encodable, Sendable {
        let user: TestModel
        let active: Bool
    }

    @Test("asDictionary preserves string and int values")
    func asDictionary_preservesValues() {
        let model = TestModel(name: "Test", age: 25)
        let dict = model.asDictionary()
        #expect(dict["name"] as? String == "Test")
        #expect(dict["age"] as? Int == 25)
    }

    @Test("asDictionary handles nested objects")
    func asDictionary_nestedObjects() {
        let model = NestedModel(user: TestModel(name: "Nested", age: 30), active: true)
        let dict = model.asDictionary()
        let userDict = dict["user"] as? [String: Any]
        #expect(userDict?["name"] as? String == "Nested")
        #expect(userDict?["age"] as? Int == 30)
        #expect(dict["active"] as? Bool == true)
    }

    @Test("asDictionary returns empty dict for encoding failure")
    func asDictionary_emptyOnFailure() {
        let model = EmptyRequestContent()
        let dict = model.asDictionary()
        #expect(dict.isEmpty)
    }

    @Test("jsonData encodes correctly")
    func jsonData_encodesCorrectly() throws {
        let model = TestModel(name: "JSON", age: 42)
        let data = try #require(model.jsonData)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["name"] as? String == "JSON")
        #expect(decoded?["age"] as? Int == 42)
    }

    @Test("jsonData returns nil-safe for valid types")
    func jsonData_returnsData() {
        let model = TestModel(name: "Test", age: 1)
        #expect(model.jsonData != nil)
    }
}
