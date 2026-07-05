import AppKit
import Foundation

enum PasswordFormAction: String, Codable {
    case login
    case createAccount
}

enum PasswordAutofillFieldKind: String, Codable {
    case email
    case password
    case username
    case oneTimeCode
    case creditCard
    case identity
}

enum PasswordAutofillKeyCommand: String, Codable {
    case moveUp
    case moveDown
    case activate
    case dismiss
}

struct PasswordBridgeRect: Codable, Equatable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double

    enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width
        case height
    }

    var cgRect: CGRect {
        CGRect(x: originX, y: originY, width: width, height: height)
    }
}

struct PasswordBridgeField: Codable, Equatable {
    let fieldID: String
    let purpose: FieldPurpose
}

struct PasswordBridgeFocusPayload: Codable, Equatable {
    let fieldID: String
    let hostname: String
    let action: PasswordFormAction
    let fieldKind: PasswordAutofillFieldKind
    let usernameFieldID: String?
    let passwordFieldIDs: [String]
    let fields: [PasswordBridgeField]?
    let rect: PasswordBridgeRect

    init(
        fieldID: String,
        hostname: String,
        action: PasswordFormAction,
        fieldKind: PasswordAutofillFieldKind,
        usernameFieldID: String?,
        passwordFieldIDs: [String],
        fields: [PasswordBridgeField]? = nil,
        rect: PasswordBridgeRect
    ) {
        self.fieldID = fieldID
        self.hostname = hostname
        self.action = action
        self.fieldKind = fieldKind
        self.usernameFieldID = usernameFieldID
        self.passwordFieldIDs = passwordFieldIDs
        self.fields = fields
        self.rect = rect
    }

    private func copy(hostname: String? = nil, rect: PasswordBridgeRect? = nil) -> PasswordBridgeFocusPayload {
        PasswordBridgeFocusPayload(
            fieldID: fieldID,
            hostname: hostname ?? self.hostname,
            action: action,
            fieldKind: fieldKind,
            usernameFieldID: usernameFieldID,
            passwordFieldIDs: passwordFieldIDs,
            fields: fields,
            rect: rect ?? self.rect
        )
    }

    func withRect(_ newRect: PasswordBridgeRect) -> PasswordBridgeFocusPayload {
        copy(rect: newRect)
    }

    func withHostname(_ newHostname: String) -> PasswordBridgeFocusPayload {
        copy(hostname: newHostname)
    }
}

struct PasswordBridgeSubmitPayload: Codable, Equatable {
    let hostname: String
    let username: String
    let password: String
    let action: PasswordFormAction
}

struct PasswordBridgeEvent: Codable, Equatable {
    let type: String
    let focus: PasswordBridgeFocusPayload?
    let submit: PasswordBridgeSubmitPayload?
    let keyCommand: PasswordAutofillKeyCommand?
    let fieldID: String?
    let rect: PasswordBridgeRect?
}

struct PasswordFillRequest: Codable {
    let usernameFieldID: String?
    let passwordFieldIDs: [String]
    let username: String?
    let password: String
    let highlightColor: String
    let submitAfterFill: Bool
}

struct PasswordMultiFillRequest: Codable {
    struct FieldEntry: Codable {
        let fieldID: String
        let value: String
    }

    let fields: [FieldEntry]
    let highlightColor: String
}
