@testable import Evo
import Foundation
import Testing

struct StructuredFocusDecodeTests {
    @Test func decodesCreditCardFocusWithFields() throws {
        let json = """
        {"type":"focus","focus":{"fieldID":"f","hostname":"shop.example.com","action":"login",
        "fieldKind":"creditCard","usernameFieldID":null,"passwordFieldIDs":[],
        "fields":[{"fieldID":"n","purpose":"cardNumber"},{"fieldID":"c","purpose":"cvv"}],
        "rect":{"x":0,"y":0,"width":1,"height":1}}}
        """
        let event = try JSONDecoder().decode(PasswordBridgeEvent.self, from: Data(json.utf8))
        #expect(event.focus?.fieldKind == .creditCard)
        #expect(event.focus?.fields?.count == 2)
        #expect(event.focus?.fields?.first?.purpose == .cardNumber)
    }
}
