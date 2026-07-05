@testable import Evo
import Foundation
import Testing

struct StructuredItemTests {
    @Test func mapsSidecarStructuredDictToItem() {
        let dict: [String: Any] = [
            "id": "c1", "vaultId": "v1", "category": "creditCard",
            "title": "Personal Visa", "subtitle": "Visa ····1234"
        ]
        let item = OnePasswordService.structured(from: dict, account: "my.1password.com")
        #expect(item?.category == .creditCard)
        #expect(item?.subtitle == "Visa ····1234")
        if case let .onePassword(account, vault, itemID) = item?.ref {
            #expect(account == "my.1password.com")
            #expect(vault == "v1")
            #expect(itemID == "c1")
        } else {
            Issue.record("expected onePassword ref")
        }
    }

    @Test func ignoresUnknownCategory() {
        let dict: [String: Any] = ["id": "x", "vaultId": "v", "category": "login", "title": "t", "subtitle": "s"]
        #expect(OnePasswordService.structured(from: dict, account: "a") == nil)
    }
}
