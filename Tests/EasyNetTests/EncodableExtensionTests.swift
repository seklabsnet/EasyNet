import Testing
import Foundation
@testable import EasyNet

@Suite("EmptyRequestContent")
struct EmptyRequestContentTests {

    @Test("EmptyRequestContent encodes to empty JSON object")
    func encodesToEmptyObject() throws {
        let model = EmptyRequestContent()
        let data = try JSONEncoder().encode(model)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?.isEmpty == true)
    }
}
