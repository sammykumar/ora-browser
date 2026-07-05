# FIELD_SCHEMA.md — assumed 1Password field IDs/types for CreditCard and Identity

Task 1.1 (an interactive dump against a real 1Password vault to confirm these field
IDs/types) was deferred. Everything below is **1Password's assumed default schema**,
UNVERIFIED against a live vault — confirm at UAT and correct `structured.go` /
`structured_test.go` if a real vault disagrees.

What *was* verified for this task: the `onepassword-sdk-go` v0.4.0 constants referenced
below (`ItemFieldType*`, `ItemCategory*`, `AddressFieldDetails`) do exist in the installed
SDK (`go list -m -f '{{.Dir}}' github.com/1password/onepassword-sdk-go` →
`types.go`). None of the brief's suggested constant names had to be substituted.

## Credit Card (`onepassword.ItemCategoryCreditCard`)

| Field ID (assumed) | Title (assumed)      | `FieldType`                       | Purpose (shared vocabulary) |
|---------------------|-----------------------|------------------------------------|------------------------------|
| `cardholder`         | "cardholder name"     | `ItemFieldTypeText`                | `cardholderName`             |
| `type`               | "type"                | `ItemFieldTypeCreditCardType`      | (used for subtitle brand, not a fill purpose) |
| `ccnum`              | "number"              | `ItemFieldTypeCreditCardNumber`    | `cardNumber`                 |
| `cvv`                | "verification number" | `ItemFieldTypeConcealed`           | `cvv`                        |
| `expiry`             | "expiry date"         | `ItemFieldTypeMonthYear`           | `expMonth` + `expYear` + `expDate` (derived) |

Notes:
- `ItemFieldTypeMonthYear` values are stored as `YYYYMM` (e.g. `"202809"` = Sep 2028).
  We derive `expMonth` (`"09"`), `expYear` (`"2028"`), and `expDate` (`"09/28"`) from it.
- The `cvv` field's `FieldType` is generic `Concealed` (1Password does not have a
  dedicated CVV field type in this SDK version) — matched by a case-insensitive field
  ID `cvv` or a title containing "verification", mirroring how `itemmap.go`'s
  `extractLogin` matches `password` by ID/title rather than by a password-specific
  `FieldType`.
- `ItemFieldTypeCreditCardType` only feeds the metadata `subtitle` (e.g. "Visa"); it is
  not part of the `fillItem` value vocabulary.
- `cardholderName` also matches on a title containing "cardholder" if the field ID
  isn't `cardholder` (see the title-keyword fallback note below).

## Identity (`onepassword.ItemCategoryIdentity`)

| Field ID (assumed)              | `FieldType`         | Purpose (shared vocabulary) |
|-----------------------------------|----------------------|------------------------------|
| `firstname`                       | `ItemFieldTypeText`  | `givenName`                  |
| `lastname`                        | `ItemFieldTypeText`  | `familyName`                 |
| `company`                         | `ItemFieldTypeText`  | `organization`                |
| `email`                           | `ItemFieldTypeText`  | `email`                       |
| `defphone` / `cellphone` / `homephone` | `ItemFieldTypeText`  | `phone` (first non-empty one wins) |
| (derived from `givenName` + `familyName`) | —          | `fullName` (space-joined, trimmed; only set if non-empty) |

Note: `email` may in practice come through the SDK as `ItemFieldTypeEmail` rather than
`ItemFieldTypeText`, and phone fields may come through as `ItemFieldTypePhone` rather
than `ItemFieldTypeText` (the SDK defines both constants). `extractFillValues` already
handles both variants defensively — a `ItemFieldTypeEmail`/`ItemFieldTypePhone` field
fills `email`/`phone` the same way a matching `ItemFieldTypeText` field would (first
non-empty value wins). This is not exercised by this task's tests because we don't have
a live vault to confirm which variant 1Password actually emits for identity email/phone
— confirm at UAT.

### Title-keyword fallback matching

Since the field IDs above are unverified assumptions, `mapTextField` matches each
purpose by field ID *or*, failing that, a lower-cased title keyword — mirroring
`itemmap.go`'s `f.ID == "x" || f.Title == "y"` convention (here using `Contains` since
title text is prose, not a fixed token). This degrades gracefully if a real vault uses
different field IDs than assumed, instead of silently dropping the value:

| Purpose          | ID match      | Title-keyword fallback (lower-cased `Contains`) |
|-------------------|----------------|---------------------------------------------------|
| `cardholderName`   | `cardholder`   | "cardholder"                                        |
| `givenName`        | `firstname`    | "first"                                             |
| `familyName`       | `lastname`     | "last"                                              |
| `organization`     | `company`      | "company" or "organization"                         |
| `email`            | `email`        | "email"                                             |
| `phone`            | `defphone` / `cellphone` / `homephone` | "phone" (first non-empty wins, same as ID match) |

`email` is also guarded to first-non-empty (won't override a value already set by an
`ItemFieldTypeEmail` field), matching the phone purposes' existing first-wins rule.

### Address

The SDK exposes a **single structured address field**, not separate
addressLine1/line2/city/state/postalCode/country text fields:

```go
type AddressFieldDetails struct {
    Street  string `json:"street"`
    City    string `json:"city"`
    Country string `json:"country"`
    Zip     string `json:"zip"`
    State   string `json:"state"`
}
```

reached via `field.FieldType == onepassword.ItemFieldTypeAddress` and
`field.Details.Address()`. We map:

| `AddressFieldDetails` | Purpose (shared vocabulary) |
|------------------------|------------------------------|
| `Street`                | `addressLine1`                |
| (none)                  | `addressLine2` — **not populated**; the SDK has no second street line |
| `City`                  | `city`                        |
| `State`                 | `state`                       |
| `Zip`                   | `postalCode`                  |
| `Country`               | `country`                     |

`addressLine2` is intentionally left absent from `fillItem`'s output for identity items
until/unless a real vault shows a second address field.
