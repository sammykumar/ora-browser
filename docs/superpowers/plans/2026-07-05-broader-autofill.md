# Broader 1Password Autofill Implementation Plan (cards, identities, HTTP Basic-auth)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill credit-card and identity/address fields from 1Password items, and offer matching logins on HTTP Basic-auth challenges — extending the existing 1Password sidecar integration.

**Architecture:** Cards + identities share one path: the Go sidecar surfaces `CreditCard`/`Identity` items as secret-free metadata (`listStructured`) and returns fillable values on demand (`fillItem`); `password-manager.js` detects card/address fields via `autocomplete` tokens + light regex and fills the whole group in one message; the Swift coordinator surfaces non-host-scoped overlay rows and drives the fill. HTTP Basic-auth is an independent branch in the existing WKWebView challenge handler that reuses the provider's login lookup + reveal.

**Tech Stack:** Go (`onepassword-sdk-go`), Swift/SwiftUI (`@MainActor` services, `PasswordProvider` seam), injected JS bridge, WKWebView delegate. XcodeGen (`project.yml`), Swift Testing (`import Testing`), Go `testing`.

## Global Constraints

- **Secrets discipline:** metadata caches carry NO secrets. Card number, CVV, and Basic-auth passwords cross the wire ONLY at fill/reveal time. Every metadata DTO/type must be leak-tested.
- **Shared field-purpose vocabulary** (used verbatim by Go extraction, JS detection, and Swift): card — `cardholderName`, `cardNumber`, `expMonth`, `expYear`, `expDate`, `cvv`; identity — `givenName`, `familyName`, `fullName`, `addressLine1`, `addressLine2`, `city`, `state`, `postalCode`, `country`, `phone`, `email`, `organization`.
- **Cards/identities are 1Password-only and NOT host-scoped** — a card/identity focus lists ALL items of that category. Login/email/OTP behavior is unchanged.
- **Fill only** — no card/identity capture/save. No SSH keys.
- After any `project.yml` change run `xcodegen`. Rebuild the sidecar with `scripts/build-op-helper.sh` after Go changes; the committed binary is `tools/op-helper/bin/evo-op-helper`.
- Sidecar builds need Go ≥1.24 + Xcode CLT (`brew install go` is fine). Swift tests: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`. Go tests: `cd tools/op-helper && go test ./...`.
- Reference spec: `docs/superpowers/specs/2026-07-05-broader-autofill-design.md`.

---

## Slice 1 — Sidecar + provider plumbing (no UI)

### Task 1.1: Discover the real 1Password field schema for CreditCard & Identity items

The `onepassword-sdk-go` field IDs/types for cards and identities must be confirmed empirically before writing extraction — guessing them produces silent mis-maps. This task adds a throwaway dump method, records the shapes, and removes it.

**Files:**
- Modify (temporary): `tools/op-helper/main.go`

- [ ] **Step 1: Add a temporary `debugDump` method to `handle`**

In `handle`'s `switch`, add before `default:`:

```go
	case "debugDump":
		item, err := c.(*sdkClient).client.Items().Get(ctx, str(req.Params, "vaultId"), str(req.Params, "itemId"))
		if err != nil {
			return fail(req.ID, "internal", err.Error())
		}
		var fields []map[string]interface{}
		for _, f := range item.Fields {
			fields = append(fields, map[string]interface{}{
				"id": f.ID, "title": f.Title, "type": string(f.FieldType), "value": f.Value,
			})
		}
		return ok(req.ID, map[string]interface{}{"category": string(item.Category), "fields": fields})
```

- [ ] **Step 2: Build the sidecar**

Run: `cd tools/op-helper && go build -o bin/evo-op-helper .`
Expected: builds with no error.

- [ ] **Step 3: Dump one real CreditCard and one real Identity item**

Find a card and an identity item's `vaultId`/`itemId` (e.g. temporarily inspect via the running app's cache, or by listing). Then drive the helper directly:
```bash
cd tools/op-helper
printf '{"id":"1","method":"debugDump","params":{"vaultId":"VAULT","itemId":"CARD_ITEM"}}\n' \
  | ./bin/evo-op-helper --account "my.1password.com"
```
Replace `VAULT`/`CARD_ITEM` with real IDs; repeat for an identity item. **Record** each field's `id`, `title`, `type` (especially: the card number, CVV, expiry (note its type — likely a month/year type), cardholder; and identity given/family name, address (may be a single structured Address field with sub-parts), phone, email). You will map these in Task 1.2.

- [ ] **Step 4: Remove the temporary `debugDump` case** and rebuild to confirm clean:

Run: `cd tools/op-helper && go build -o bin/evo-op-helper .`
Expected: builds; no `debugDump` remains (`grep debugDump *.go` returns nothing).

- [ ] **Step 5: Commit the recorded schema as a comment**

Create `tools/op-helper/FIELD_SCHEMA.md` documenting the confirmed field IDs/types for CreditCard and Identity (so Task 1.2's constants are traceable). Commit:
```bash
git add tools/op-helper/FIELD_SCHEMA.md
git commit -m "docs(op-helper): record confirmed 1Password card/identity field schema"
```

### Task 1.2: Sidecar `listStructured` + `fillItem` (Go, tested)

**Files:**
- Modify: `tools/op-helper/protocol.go` (add `structuredDTO`)
- Create: `tools/op-helper/structured.go`
- Modify: `tools/op-helper/main.go` (opClient interface + `handle` cases + gather)
- Modify: `tools/op-helper/client.go` (implement the two new sdkClient methods)
- Create: `tools/op-helper/structured_test.go`

**Interfaces:**
- Produces (wire): `listStructured` → `{items: [{id, vaultId, category, title, subtitle}]}`; `fillItem` params `{vaultId, itemId}` → `{values: {purpose: value}}`. Consumed by Slice 1 Swift tasks.

- [ ] **Step 1: Add the `structuredDTO` wire type**

In `tools/op-helper/protocol.go`, after `itemDTO`:

```go
// structuredDTO is secret-free metadata for a CreditCard or Identity item.
type structuredDTO struct {
	ID       string `json:"id"`
	VaultID  string `json:"vaultId"`
	Category string `json:"category"` // "creditCard" | "identity"
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"` // e.g. "Visa ····1234" or "Sam Kumar" — NEVER full PAN/CVV
}
```

- [ ] **Step 2: Write failing extraction tests**

Create `tools/op-helper/structured_test.go` (use the field IDs/types confirmed in Task 1.1 — the IDs below are the 1Password defaults; correct them to match `FIELD_SCHEMA.md` if they differ):

```go
package main

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/1password/onepassword-sdk-go"
)

func cardItem() onepassword.Item {
	return onepassword.Item{
		ID: "c1", VaultID: "v1", Title: "Personal Visa", Category: onepassword.ItemCategoryCreditCard,
		Fields: []onepassword.ItemField{
			{ID: "cardholder", Title: "cardholder name", FieldType: onepassword.ItemFieldTypeText, Value: "Sam Kumar"},
			{ID: "ccnum", Title: "number", FieldType: onepassword.ItemFieldTypeCreditCardNumber, Value: "4111111111111234"},
			{ID: "cvv", Title: "verification number", FieldType: onepassword.ItemFieldTypeConcealed, Value: "123"},
			{ID: "expiry", Title: "expiry date", FieldType: onepassword.ItemFieldTypeMonthYear, Value: "202809"},
		},
	}
}

func TestCardToStructuredHasNoSecretsInSubtitle(t *testing.T) {
	dto := itemToStructured("v1", cardItem())
	if dto.Category != "creditCard" {
		t.Fatalf("category = %q", dto.Category)
	}
	blob, _ := json.Marshal(dto)
	if strings.Contains(string(blob), "4111111111111234") || strings.Contains(string(blob), "123") {
		t.Fatalf("secret leaked into metadata: %s", blob)
	}
	if !strings.Contains(dto.Subtitle, "1234") { // last-4 is allowed and expected
		t.Fatalf("subtitle should show last-4, got %q", dto.Subtitle)
	}
}

func TestExtractFillValuesCard(t *testing.T) {
	v := extractFillValues(cardItem())
	if v["cardNumber"] != "4111111111111234" {
		t.Fatalf("cardNumber = %q", v["cardNumber"])
	}
	if v["cvv"] != "123" {
		t.Fatalf("cvv = %q", v["cvv"])
	}
	if v["expMonth"] != "09" || v["expYear"] != "2028" || v["expDate"] != "09/28" {
		t.Fatalf("expiry map wrong: %q %q %q", v["expMonth"], v["expYear"], v["expDate"])
	}
	if v["cardholderName"] != "Sam Kumar" {
		t.Fatalf("cardholderName = %q", v["cardholderName"])
	}
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd tools/op-helper && go test ./... -run 'Card|FillValues'`
Expected: FAIL — `itemToStructured`/`extractFillValues` undefined.

- [ ] **Step 4: Implement `structured.go`**

Create `tools/op-helper/structured.go`. Adjust field-ID/type matching to `FIELD_SCHEMA.md`:

```go
package main

import (
	"fmt"
	"strings"

	"github.com/1password/onepassword-sdk-go"
)

// itemToStructured builds secret-free metadata for a card/identity item.
func itemToStructured(vaultID string, full onepassword.Item) structuredDTO {
	dto := structuredDTO{ID: full.ID, VaultID: vaultID, Title: full.Title}
	switch full.Category {
	case onepassword.ItemCategoryCreditCard:
		dto.Category = "creditCard"
		dto.Subtitle = cardSubtitle(full)
	case onepassword.ItemCategoryIdentity:
		dto.Category = "identity"
		dto.Subtitle = identitySubtitle(full)
	}
	return dto
}

// cardSubtitle returns e.g. "Visa ····1234" using only the last 4 digits (not sensitive).
func cardSubtitle(item onepassword.Item) string {
	var brand, last4 string
	for _, f := range item.Fields {
		switch f.FieldType {
		case onepassword.ItemFieldTypeCreditCardType:
			brand = f.Value
		case onepassword.ItemFieldTypeCreditCardNumber:
			digits := strings.Map(func(r rune) rune {
				if r >= '0' && r <= '9' {
					return r
				}
				return -1
			}, f.Value)
			if len(digits) >= 4 {
				last4 = digits[len(digits)-4:]
			}
		}
	}
	sub := strings.TrimSpace(brand)
	if last4 != "" {
		sub = strings.TrimSpace(sub + " ····" + last4)
	}
	if sub == "" {
		sub = item.Title
	}
	return sub
}

func identitySubtitle(item onepassword.Item) string {
	vals := extractFillValues(item)
	if n := strings.TrimSpace(vals["fullName"]); n != "" {
		return n
	}
	name := strings.TrimSpace(vals["givenName"] + " " + vals["familyName"])
	if name != "" {
		return name
	}
	if e := vals["email"]; e != "" {
		return e
	}
	return item.Title
}

// extractFillValues maps a card/identity item's fields to the shared purpose vocabulary.
func extractFillValues(item onepassword.Item) map[string]string {
	out := map[string]string{}
	for _, f := range item.Fields {
		switch f.FieldType {
		case onepassword.ItemFieldTypeCreditCardNumber:
			out["cardNumber"] = f.Value
		case onepassword.ItemFieldTypeConcealed:
			if f.ID == "cvv" || strings.Contains(strings.ToLower(f.Title), "verification") {
				out["cvv"] = f.Value
			}
		case onepassword.ItemFieldTypeMonthYear:
			// 1Password stores YYYYMM (e.g. "202809").
			if len(f.Value) == 6 {
				yyyy, mm := f.Value[0:4], f.Value[4:6]
				out["expMonth"] = mm
				out["expYear"] = yyyy
				out["expDate"] = fmt.Sprintf("%s/%s", mm, yyyy[2:])
			}
		case onepassword.ItemFieldTypeText:
			mapTextField(f, out)
		}
	}
	return out
}

// mapTextField maps text fields by ID/title to card/identity purposes.
// IDs come from FIELD_SCHEMA.md; extend as needed.
func mapTextField(f onepassword.ItemField, out map[string]string) {
	id := strings.ToLower(f.ID)
	switch id {
	case "cardholder":
		out["cardholderName"] = f.Value
	case "firstname":
		out["givenName"] = f.Value
	case "lastname":
		out["familyName"] = f.Value
	case "company":
		out["organization"] = f.Value
	case "email":
		out["email"] = f.Value
	case "defphone", "cellphone", "homephone":
		if out["phone"] == "" {
			out["phone"] = f.Value
		}
	}
}
```

> **Note on Identity address:** if Task 1.1 shows the identity address is a single structured `ItemFieldTypeAddress` (with `f.Details.Address()` sub-parts), add a `case onepassword.ItemFieldTypeAddress:` in `extractFillValues` that reads `Details.Address()` and fills `addressLine1`/`city`/`state`/`postalCode`/`country`. If it is separate text fields, extend `mapTextField`. Match what the schema showed.

- [ ] **Step 5: Run extraction tests to verify pass**

Run: `cd tools/op-helper && go test ./... -run 'Card|FillValues'`
Expected: PASS. (If field IDs differ from the defaults, correct them per `FIELD_SCHEMA.md` until green.)

- [ ] **Step 6: Add the `opClient` methods + `handle` cases + client impl**

In `tools/op-helper/main.go`, add to the `opClient` interface:
```go
	listStructured(ctx context.Context, vaultID string) ([]structuredDTO, error)
	fillItem(ctx context.Context, vaultID, itemID string) (map[string]string, error)
```
Add to `handle`'s switch before `default:`:
```go
	case "listStructured":
		items, err := gatherStructured(ctx, c)
		if err != nil {
			code, msg := mapSDKError(err)
			return fail(req.ID, code, msg)
		}
		return ok(req.ID, map[string]interface{}{"items": items})
	case "fillItem":
		values, err := c.fillItem(ctx, str(req.Params, "vaultId"), str(req.Params, "itemId"))
		if err != nil {
			code, msg := mapSDKError(err)
			return fail(req.ID, code, msg)
		}
		return ok(req.ID, map[string]interface{}{"values": values})
```
Add the gather helper (mirrors `gatherItems`) in `main.go`:
```go
func gatherStructured(ctx context.Context, c opClient) ([]structuredDTO, error) {
	vaults, err := c.listVaults(ctx)
	if err != nil {
		return nil, err
	}
	var out []structuredDTO
	for _, v := range vaults {
		items, err := c.listStructured(ctx, v.ID)
		if err != nil {
			return nil, err
		}
		out = append(out, items...)
	}
	return out, nil
}
```
In `tools/op-helper/client.go`, implement (mirrors `listItems`'s chunked GetAll, filtering to the two categories):
```go
func (s *sdkClient) listStructured(ctx context.Context, vaultID string) ([]structuredDTO, error) {
	overviews, err := s.client.Items().List(ctx, vaultID,
		onepassword.NewItemListFilterTypeVariantByState(
			&onepassword.ItemListFilterByStateInner{Active: true, Archived: false}))
	if err != nil {
		return nil, err
	}
	var ids []string
	for _, ov := range overviews {
		if ov.Category == onepassword.ItemCategoryCreditCard || ov.Category == onepassword.ItemCategoryIdentity {
			ids = append(ids, ov.ID)
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}
	out := make([]structuredDTO, 0, len(ids))
	for _, chunk := range chunkIDs(ids, getAllBatchLimit) {
		batch, err := s.client.Items().GetAll(ctx, vaultID, chunk)
		if err != nil {
			return nil, err
		}
		for _, res := range batch.IndividualResponses {
			if res.Content == nil {
				continue
			}
			out = append(out, itemToStructured(vaultID, *res.Content))
		}
	}
	return out, nil
}

func (s *sdkClient) fillItem(ctx context.Context, vaultID, itemID string) (map[string]string, error) {
	item, err := s.client.Items().Get(ctx, vaultID, itemID)
	if err != nil {
		return nil, err
	}
	return extractFillValues(item), nil
}
```

- [ ] **Step 7: Build sidecar + run full Go suite**

Run: `cd tools/op-helper && go build -o bin/evo-op-helper . && go test ./...`
Expected: build OK; all tests PASS.

- [ ] **Step 8: Rebuild the committed binary and commit**

Run: `./scripts/build-op-helper.sh`
```bash
git add tools/op-helper/protocol.go tools/op-helper/structured.go tools/op-helper/structured_test.go tools/op-helper/main.go tools/op-helper/client.go tools/op-helper/bin/evo-op-helper
git commit -m "feat(op-helper): listStructured + fillItem for cards and identities"
```

### Task 1.3: Swift provider types + protocol methods (tested)

**Files:**
- Modify: `evo/Features/Passwords/Providers/PasswordProviderTypes.swift`
- Modify: `evo/Features/Passwords/Providers/PasswordProvider.swift`
- Modify: `evo/Features/Passwords/Providers/EvoPasswordProvider.swift`
- Modify: `evo/Features/Passwords/Providers/OnePasswordProvider.swift`
- Modify: `evo/Features/Passwords/Services/OnePasswordService.swift`
- Create: `evoTests/Passwords/StructuredItemTests.swift`

**Interfaces:**
- Produces: `FieldPurpose`, `StructuredCategory`, `ProviderStructuredItem`; `PasswordProvider.structuredItems(_:)` / `.fillValues(for:)`; `OnePasswordService.structuredMetadata`, `.structuredItems(_:)`, `.fillValues(for:)`. Consumed by Slices 2–4.

- [ ] **Step 1: Add the shared types**

In `PasswordProviderTypes.swift`, add:
```swift
/// Fields Evo can fill across cards and identities. Raw values are the shared vocabulary
/// mirrored by password-manager.js and the Go sidecar's extraction.
enum FieldPurpose: String, Codable, Hashable, Sendable {
    case cardholderName, cardNumber, expMonth, expYear, expDate, cvv
    case givenName, familyName, fullName
    case addressLine1, addressLine2, city, state, postalCode, country
    case phone, email, organization
}

enum StructuredCategory: String, Codable, Hashable, Sendable {
    case creditCard, identity
}

/// Secret-free metadata for a card/identity item surfaced to the overlay.
struct ProviderStructuredItem: Identifiable, Hashable, Sendable {
    let id: String
    let ref: ProviderItemRef
    let category: StructuredCategory
    let title: String
    let subtitle: String
}
```

- [ ] **Step 2: Write failing tests**

Create `evoTests/Passwords/StructuredItemTests.swift`:
```swift
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
```

- [ ] **Step 3: Run to verify failure**

Run: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/StructuredItemTests 2>&1 | xcbeautify`
Expected: FAIL — `structured(from:account:)` undefined.

- [ ] **Step 4: Add protocol methods (default no-op) + implementations**

In `PasswordProvider.swift`, add to the protocol:
```swift
    func structuredItems(_ category: StructuredCategory) async -> [ProviderStructuredItem]
    func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String]
```
In `EvoPasswordProvider.swift`, add (Keychain has no such items):
```swift
    nonisolated func structuredItems(_ category: StructuredCategory) async -> [ProviderStructuredItem] { [] }
    nonisolated func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String] { [:] }
```
In `OnePasswordProvider.swift`, add:
```swift
    nonisolated func structuredItems(_ category: StructuredCategory) async -> [ProviderStructuredItem] {
        await service.ensureConfigured()
        return await MainActor.run { service.structuredItems(category) }
    }

    nonisolated func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String] {
        try await service.fillValues(for: ref)
    }
```

- [ ] **Step 5: Extend `OnePasswordService` with the structured cache + mapper + calls**

In `OnePasswordService.swift`, add a published cache next to `metadata`:
```swift
    @Published private(set) var structuredMetadata: [ProviderStructuredItem] = []
```
Add the static mapper (mirrors the existing `credential(from:account:)`):
```swift
    static func structured(from dict: [String: Any], account: String) -> ProviderStructuredItem? {
        guard let id = dict["id"] as? String,
              let vaultID = dict["vaultId"] as? String,
              let categoryRaw = dict["category"] as? String,
              let category = StructuredCategory(rawValue: categoryRaw)
        else { return nil }
        return ProviderStructuredItem(
            id: id,
            ref: .onePassword(accountName: account, vaultID: vaultID, itemID: id),
            category: category,
            title: dict["title"] as? String ?? "",
            subtitle: dict["subtitle"] as? String ?? ""
        )
    }

    func structuredItems(_ category: StructuredCategory) -> [ProviderStructuredItem] {
        structuredMetadata.filter { $0.category == category }
    }

    func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String] {
        guard case let .onePassword(accountName, vaultID, itemID) = ref,
              let process = processes[accountName]
        else { throw OpHelperError.notRunning }
        let result = try await process.request(method: "fillItem", params: ["vaultId": vaultID, "itemId": itemID])
        let raw = result["values"] as? [String: String] ?? [:]
        var out: [FieldPurpose: String] = [:]
        for (key, value) in raw {
            if let purpose = FieldPurpose(rawValue: key) { out[purpose] = value }
        }
        return out
    }
```
In `refresh()`, after the existing per-account `listItems` block populates `merged`, also fetch structured items. Inside the `for account in accounts` loop, after the `do`/`catch` that appends logins, add a second guarded call:
```swift
            if let process = processes[account] {
                if let result = try? await process.request(method: "listStructured", params: [:]),
                   let items = result["items"] as? [[String: Any]] {
                    structuredMerged.append(contentsOf: items.compactMap { Self.structured(from: $0, account: account) })
                }
            }
```
Declare `var structuredMerged: [ProviderStructuredItem] = []` alongside `merged`, and after the loop assign `structuredMetadata = structuredMerged`. (Structured fetch failures are non-fatal — they must not change the login-derived `state`.)

- [ ] **Step 6: Run tests to verify pass**

Run: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/StructuredItemTests 2>&1 | xcbeautify`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add evo/Features/Passwords evoTests/Passwords/StructuredItemTests.swift
git commit -m "feat(passwords): provider seam for structured (card/identity) items"
```

---

## Slice 2 — JS detection + multi-field fill

### Task 2.1: Detect card/identity fields and emit the field group

**Files:**
- Modify: `evo/Resources/WebScripts/password-manager.js`
- Modify: `evo/Features/Passwords/Services/PasswordAutofillCoordinator.swift` (payload + fieldKind)
- Create: `evoTests/Passwords/StructuredFocusDecodeTests.swift`

**Interfaces:**
- Produces: focus payloads with `fieldKind` `creditCard`/`identity` and a `fields: [{fieldID, purpose}]` array; the JS `__evoPasswordManager.fillFields` handler. Consumed by Slices 3–4.

- [ ] **Step 1: Add the purpose map + detector to `password-manager.js`**

Near the top helpers, add the autocomplete→purpose map and a detector:
```javascript
    const AUTOCOMPLETE_PURPOSE = {
        "cc-name": "cardholderName", "cc-number": "cardNumber", "cc-exp": "expDate",
        "cc-exp-month": "expMonth", "cc-exp-year": "expYear", "cc-csc": "cvv",
        "given-name": "givenName", "family-name": "familyName", "name": "fullName",
        "street-address": "addressLine1", "address-line1": "addressLine1", "address-line2": "addressLine2",
        "address-level2": "city", "address-level1": "state", "postal-code": "postalCode",
        "country": "country", "country-name": "country", "tel": "phone", "email": "email",
        "organization": "organization"
    };

    function tokenPurpose(element) {
        const ac = (element.autocomplete || "").toLowerCase().trim();
        // autocomplete may be "section-foo shipping cc-number"; take the last known token.
        const parts = ac.split(/\s+/);
        for (let i = parts.length - 1; i >= 0; i--) {
            if (AUTOCOMPLETE_PURPOSE[parts[i]]) return AUTOCOMPLETE_PURPOSE[parts[i]];
        }
        return regexPurpose(element);
    }

    function regexPurpose(element) {
        const hay = [element.name, element.id, element.placeholder, element.getAttribute("aria-label")]
            .filter(Boolean).join(" ").toLowerCase();
        if (/card.?number|ccnum|cardnum/.test(hay)) return "cardNumber";
        if (/(^|[^a-z])(cvv|cvc|csc)([^a-z]|$)/.test(hay)) return "cvv";
        if (/exp.*month/.test(hay)) return "expMonth";
        if (/exp.*year/.test(hay)) return "expYear";
        if (/expir/.test(hay)) return "expDate";
        if (/cardholder|name.*card/.test(hay)) return "cardholderName";
        if (/postal|zip/.test(hay)) return "postalCode";
        if (/address.*1|street/.test(hay)) return "addressLine1";
        return null;
    }

    const CARD_PURPOSES = new Set(["cardholderName","cardNumber","expMonth","expYear","expDate","cvv"]);

    function purposeGroupKind(purpose) {
        if (!purpose) return null;
        return CARD_PURPOSES.has(purpose) ? "creditCard" : "identity";
    }
```

- [ ] **Step 2: Extend `fieldKindFor` and `relevantFieldsFor`/`focusPayload`**

In `fieldKindFor`, after the `oneTimeCode` check and before `return null;`:
```javascript
        const purpose = tokenPurpose(element);
        const groupKind = purposeGroupKind(purpose);
        if (groupKind) {
            return groupKind; // "creditCard" | "identity"
        }
```
Add a helper that collects the sibling structured fields, and include them in the focus payload. Add after `relevantFieldsFor`:
```javascript
    function structuredGroupFor(element, groupKind) {
        const scope = element.form || element.closest("form") || document;
        const fields = [];
        Array.from(scope.querySelectorAll("input"))
            .filter(isRelevantInput).filter(isVisible)
            .forEach((input) => {
                const purpose = tokenPurpose(input);
                if (purpose && purposeGroupKind(purpose) === groupKind) {
                    fields.push({ fieldID: ensureFieldID(input), purpose });
                }
            });
        return fields;
    }
```
In `focusPayload`, after computing `fieldKind`, branch: if `fieldKind` is `creditCard`/`identity`, return a payload carrying `fields` instead of username/password IDs:
```javascript
        if (fieldKind === "creditCard" || fieldKind === "identity") {
            return {
                fieldID: ensureFieldID(element),
                hostname: window.location.hostname,
                action: "login",
                fieldKind,
                usernameFieldID: null,
                passwordFieldIDs: [],
                fields: structuredGroupFor(element, fieldKind),
                rect: rectPayload(element)
            };
        }
```
(Keep the existing return for login/email/OTP kinds; add `fields: []` to it if simpler to keep the shape uniform — optional.)

Note: `focusPayload` currently short-circuits when `relevantFieldsFor(element)` returns `null`. Card/identity fields make it return null. Restructure so the `fieldKind` computation happens first: compute `fieldKind = fieldKindFor(element)`; if it is a structured kind, return the structured payload BEFORE calling `relevantFieldsFor`. Only fall through to the group logic for login kinds.

- [ ] **Step 3: Add the `fillFields` JS handler**

In the `window.__evoPasswordManager = { ... }` object, add:
```javascript
        fillFields(payload) {
            const request = typeof payload === "string" ? JSON.parse(payload) : payload;
            const highlightColor = request.highlightColor || "#E8F5E9";
            (request.fields || []).forEach((entry) => {
                const el = fieldByID(entry.fieldID);
                if (el && typeof entry.value === "string") {
                    fillField(el, entry.value, highlightColor);
                }
            });
        },
```

- [ ] **Step 4: Extend the Swift payload + fieldKind**

In `PasswordAutofillCoordinator.swift`, add to `PasswordAutofillFieldKind`:
```swift
    case creditCard
    case identity
```
Add a bridge field type and extend the focus payload:
```swift
struct PasswordBridgeField: Codable, Equatable {
    let fieldID: String
    let purpose: FieldPurpose
}
```
Add `let fields: [PasswordBridgeField]?` to `PasswordBridgeFocusPayload` (optional so existing login payloads decode unchanged). Add a multi-fill request + JS invocation:
```swift
struct PasswordMultiFillRequest: Codable {
    let fields: [FieldEntry]
    let highlightColor: String
    struct FieldEntry: Codable { let fieldID: String; let value: String }
}
```

- [ ] **Step 5: Write + run the focus-decode test**

Create `evoTests/Passwords/StructuredFocusDecodeTests.swift`:
```swift
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
```
Run: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/StructuredFocusDecodeTests 2>&1 | xcbeautify`
Expected: FAIL then PASS after the payload changes compile.

- [ ] **Step 6: Build + commit**

Run: `./scripts/xcbuild-debug.sh`
```bash
git add evo/Resources/WebScripts/password-manager.js evo/Features/Passwords/Services/PasswordAutofillCoordinator.swift evoTests/Passwords/StructuredFocusDecodeTests.swift
git commit -m "feat(passwords): JS detection + Swift payload for card/identity field groups"
```

---

## Slice 3 — Credit-card overlay + fill wiring

### Task 3.1: Surface card suggestions and fill on selection

**Files:**
- Modify: `evo/Features/Passwords/Services/PasswordAutofillCoordinator.swift` (suggestion case, resolve, fill)
- Modify: the overlay SwiftUI view that renders `PasswordAutofillSuggestion` rows (locate: `grep -rl "case .savedCredential" evo/Features/Passwords/Views`)
- Modify: `PasswordAutofillOverlayState` (carry structured items + focus fields)
- Create/extend: `evoTests/Passwords/StructuredResolveTests.swift`

**Interfaces:**
- Consumes: `OnePasswordService.structuredItems(.creditCard)`, `fillValues(for:)`, focus `fields` (Slice 2).
- Produces: `.fillCard(ProviderStructuredItem)` suggestion + `fillCard(_:for:)` on the coordinator.

- [ ] **Step 1: Add the suggestion case**

In `PasswordAutofillSuggestion`, add:
```swift
    case fillCard(ProviderStructuredItem)
```
Add to its `id`:
```swift
        case let .fillCard(item):
            return "card-\(item.id)"
```
and to `host` return `""` (cards aren't host-scoped).

- [ ] **Step 2: Carry structured items + focus fields in overlay state**

Add to `PasswordAutofillOverlayState`: `let structuredItems: [ProviderStructuredItem]` (default `[]` in the init). The `focus` already carries `fields` after Slice 2.

- [ ] **Step 3: Write the failing resolve test**

Create `evoTests/Passwords/StructuredResolveTests.swift`:
```swift
@testable import Evo
import Foundation
import Testing

struct StructuredResolveTests {
    private func cardFocus() -> PasswordBridgeFocusPayload {
        PasswordBridgeFocusPayload(
            fieldID: "n", hostname: "shop.example.com", action: .login, fieldKind: .creditCard,
            usernameFieldID: nil, passwordFieldIDs: [],
            fields: [PasswordBridgeField(fieldID: "n", purpose: .cardNumber)],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )
    }

    @Test func cardFocusSurfacesAllCardsNotHostFiltered() {
        let cards = [
            ProviderStructuredItem(id: "c1", ref: .onePassword(accountName: "a", vaultID: "v", itemID: "c1"),
                                   category: .creditCard, title: "Visa", subtitle: "Visa ····1234"),
            ProviderStructuredItem(id: "c2", ref: .onePassword(accountName: "a", vaultID: "v", itemID: "c2"),
                                   category: .creditCard, title: "Amex", subtitle: "Amex ····9000")
        ]
        let state = PasswordAutofillCoordinator.resolveSuggestions(
            for: cardFocus(), matchingEntries: [], emailSuggestions: [],
            generatedPassword: nil, structuredItems: cards
        )
        #expect(state.suggestions.map(\.id) == ["card-c1", "card-c2"])
    }
}
```
(Match the exact current `resolveSuggestions` signature; add the new `structuredItems:` parameter with a default `[]` so existing call sites and tests compile.)

- [ ] **Step 4: Run to verify failure**

Run: `xcodebuild test ... -only-testing:evoTests/StructuredResolveTests` (full flags as above)
Expected: FAIL (parameter/case missing).

- [ ] **Step 5: Implement resolve + fill**

In `resolveSuggestions`, add a `structuredItems: [ProviderStructuredItem] = []` parameter. At the top, branch on the structured kinds before the login logic:
```swift
        if focus.fieldKind == .creditCard {
            let cards = structuredItems.filter { $0.category == .creditCard }
            return PasswordAutofillOverlayState(
                focus: focus, savedPasswordEntries: [], emailSuggestions: [],
                generatedPassword: nil, structuredItems: cards, selectedSuggestionIndex: 0
            )
        }
```
Ensure the overlay state's `suggestions` computed property emits `.fillCard` rows for `structuredItems` when `focus.fieldKind == .creditCard`. Add the coordinator fill method:
```swift
    func fillCard(_ item: ProviderStructuredItem, for overlay: PasswordAutofillOverlayState) {
        Task { @MainActor in
            guard let values = try? await activeProvider.fillValues(for: item.ref) else { return }
            let entries: [PasswordMultiFillRequest.FieldEntry] = (overlay.focus.fields ?? []).compactMap { field in
                guard let value = values[field.purpose] else { return nil }
                return PasswordMultiFillRequest.FieldEntry(fieldID: field.fieldID, value: value)
            }
            guard !entries.isEmpty else { return }
            let request = PasswordMultiFillRequest(fields: entries, highlightColor: "#E8F5E9")
            self.evaluate(scriptMethod: "fillFields", payload: request)
        }
    }
```
(Use the same `activeProvider` reference the coordinator already uses for logins; match its actual name.)

- [ ] **Step 6: Render the row + wire selection**

In the overlay view, add a rendering branch for `.fillCard(item)` showing a card glyph + `item.title` + `item.subtitle`, and on activation call `coordinator.fillCard(item, for: overlayState)`. Populate the overlay state's `structuredItems` where the coordinator builds it (feed `service.structuredItems(.creditCard)` when the focus is a card).

- [ ] **Step 7: Run tests + build**

Run the resolve test (PASS), then `./scripts/xcbuild-debug.sh` (BUILD SUCCEEDED).

- [ ] **Step 8: Commit**

```bash
git add evo/Features/Passwords evoTests/Passwords/StructuredResolveTests.swift
git commit -m "feat(passwords): credit-card overlay rows and multi-field fill"
```

---

## Slice 4 — Identity/address overlay + fill wiring

### Task 4.1: Surface identity suggestions and fill (reuses Slice 3 infra)

**Files:**
- Modify: `evo/Features/Passwords/Services/PasswordAutofillCoordinator.swift`
- Modify: the overlay view
- Extend: `evoTests/Passwords/StructuredResolveTests.swift`

- [ ] **Step 1: Add `.fillIdentity` suggestion case** (mirrors `.fillCard`): `id` → `"identity-\(item.id)"`, `host` → `""`.

- [ ] **Step 2: Extend `resolveSuggestions`** with an identity branch mirroring the card branch:
```swift
        if focus.fieldKind == .identity {
            let ids = structuredItems.filter { $0.category == .identity }
            return PasswordAutofillOverlayState(
                focus: focus, savedPasswordEntries: [], emailSuggestions: [],
                generatedPassword: nil, structuredItems: ids, selectedSuggestionIndex: 0
            )
        }
```
Have the overlay `suggestions` emit `.fillIdentity` rows for identity focuses.

- [ ] **Step 3: Reuse the fill path** — the existing `fillCard` logic is category-agnostic (it maps focus fields to `fillValues`). Rename it to `fillStructured(_:for:)` and call it for both `.fillCard` and `.fillIdentity` activations (the value map + focus.fields handle the field set difference). Update Slice 3's call site accordingly.

- [ ] **Step 4: Add the identity resolve test**

Append to `StructuredResolveTests.swift`:
```swift
    @Test func identityFocusSurfacesAllIdentities() {
        let ids = [ProviderStructuredItem(id: "i1", ref: .onePassword(accountName: "a", vaultID: "v", itemID: "i1"),
                                          category: .identity, title: "Home", subtitle: "Sam Kumar")]
        let focus = PasswordBridgeFocusPayload(
            fieldID: "a", hostname: "shop.example.com", action: .login, fieldKind: .identity,
            usernameFieldID: nil, passwordFieldIDs: [],
            fields: [PasswordBridgeField(fieldID: "a", purpose: .addressLine1)],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )
        let state = PasswordAutofillCoordinator.resolveSuggestions(
            for: focus, matchingEntries: [], emailSuggestions: [], generatedPassword: nil, structuredItems: ids
        )
        #expect(state.suggestions.map(\.id) == ["identity-i1"])
    }
```

- [ ] **Step 5: Run tests + build + commit**

Run the resolve tests (PASS) + `./scripts/xcbuild-debug.sh`.
```bash
git add evo/Features/Passwords evoTests/Passwords/StructuredResolveTests.swift
git commit -m "feat(passwords): identity/address overlay rows and fill"
```

---

## Slice 5 — HTTP Basic-auth fill (independent)

### Task 5.1: Offer matching logins on Basic/Digest/NTLM challenges

**Files:**
- Modify: `evo/Core/BrowserEngine/BrowserPage.swift:350-363` (challenge handler)
- Modify: `evo/Core/BrowserEngine/BrowserPageDelegate.swift` (new delegate method — locate the protocol: `grep -rn "protocol BrowserPageDelegate" evo`)
- Create: `evo/Features/Passwords/Views/BasicAuthPromptView.swift` (SwiftUI picker)
- Modify: the delegate implementer that owns the active provider/coordinator (locate: `grep -rn "func browserPage(" evo/Features/Browser`)
- Create: `evoTests/Passwords/BasicAuthResolveTests.swift`

**Interfaces:**
- Consumes: `PasswordProvider.credentials(for:)` + `reveal(_:)`.
- Produces: `browserPage(_:didReceiveHTTPAuthChallengeForHost:completion:)` delegate hop; `BasicAuthPromptModel` (testable match/branch logic).

- [ ] **Step 1: Write the failing branch-logic test**

Create `evoTests/Passwords/BasicAuthResolveTests.swift`:
```swift
@testable import Evo
import Foundation
import Testing

struct BasicAuthResolveTests {
    @Test func fallsThroughAfterAPriorFailure() {
        // previousFailureCount > 0 must not re-prompt (avoid auth loops).
        #expect(BasicAuthPromptModel.shouldPrompt(matchCount: 2, previousFailureCount: 1) == false)
    }
    @Test func promptsWhenMatchesAndNoPriorFailure() {
        #expect(BasicAuthPromptModel.shouldPrompt(matchCount: 2, previousFailureCount: 0) == true)
    }
    @Test func fallsThroughWhenNoMatches() {
        #expect(BasicAuthPromptModel.shouldPrompt(matchCount: 0, previousFailureCount: 0) == false)
    }
}
```

- [ ] **Step 2: Add `BasicAuthPromptModel` with the decision rule**

In `BasicAuthPromptView.swift`:
```swift
import SwiftUI

enum BasicAuthPromptModel {
    /// Prompt only when we have candidate logins and the challenge hasn't already failed
    /// with our credentials (previousFailureCount > 0 → let WebKit show its own dialog).
    static func shouldPrompt(matchCount: Int, previousFailureCount: Int) -> Bool {
        matchCount > 0 && previousFailureCount == 0
    }
}
```

- [ ] **Step 3: Run test to verify pass** (logic-only): run `-only-testing:evoTests/BasicAuthResolveTests`. Expected: PASS.

- [ ] **Step 4: Add the delegate method + branch the challenge handler**

In the `BrowserPageDelegate` protocol, add:
```swift
    func browserPage(
        _ page: BrowserPage,
        didReceiveHTTPAuthChallengeForHost host: String,
        completion: @escaping (URLCredential?) -> Void
    )
```
In `BrowserPage.swift`, restructure the challenge handler (lines 355–362) to add the Basic/Digest/NTLM branch while leaving server-trust and default untouched:
```swift
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust,
           sslBypassedHosts.contains(challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else if (method == NSURLAuthenticationMethodHTTPBasic
                    || method == NSURLAuthenticationMethodHTTPDigest
                    || method == NSURLAuthenticationMethodNTLM),
                  challenge.previousFailureCount == 0,
                  let delegate {
            delegate.browserPage(self, didReceiveHTTPAuthChallengeForHost: challenge.protectionSpace.host) { credential in
                if let credential {
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
```

- [ ] **Step 5: Implement the delegate hop (lookup → prompt → reveal → complete)**

In the delegate implementer that owns the active provider, implement the new method: build `URL` from the host (`https://<host>/`), call `activeProvider.credentials(for: url, containerID:)`; if `BasicAuthPromptModel.shouldPrompt` is false, `completion(nil)`; otherwise present `BasicAuthPromptView` (list `title` + `displayUsername`) in an `NSPanel` sheet on the page's window. On selection: `let revealed = try await activeProvider.reveal(chosen)` → `completion(URLCredential(user: revealed.username, password: revealed.password, persistence: .forSession))`. On cancel: `completion(nil)`.

- [ ] **Step 6: Build the picker view**

Add to `BasicAuthPromptView.swift` a minimal SwiftUI list of the matching `ProviderCredential`s with Fill/Cancel actions, invoking a completion closure with the chosen credential or `nil`.

- [ ] **Step 7: Build + commit**

Run: `./scripts/xcbuild-debug.sh` (BUILD SUCCEEDED) and the Basic-auth test (PASS).
```bash
git add evo/Core/BrowserEngine evo/Features/Passwords/Views/BasicAuthPromptView.swift evo/Features/Browser evoTests/Passwords/BasicAuthResolveTests.swift
git commit -m "feat(passwords): fill logins on HTTP Basic-auth challenges"
```

---

## Slice 6 — Manual UAT

No automated test covers actual fill (page/OS-brokered). **User in UAT = Sam.** Run on a fresh `./scripts/xcbuild-debug.sh` build with 1Password unlocked.

- [ ] **UAT-1 — Card fill:** On a checkout with a card form (e.g. Stripe's test checkout), focus the card-number field → overlay lists your cards → select one → number, expiry, CVV, cardholder all fill.
- [ ] **UAT-2 — Card fill, single expiry field:** On a form with one `MM/YY` expiry field, confirm `expDate` fills correctly.
- [ ] **UAT-3 — Identity fill:** On a shipping-address form, focus the address/name field → overlay lists identities → select → address block fills.
- [ ] **UAT-4 — Un-annotated form (regex fallback):** On a checkout lacking `autocomplete` attributes, confirm card fields still detect (or note the miss as an accepted limitation).
- [ ] **UAT-5 — Not host-scoped:** Confirm cards/identities appear regardless of site.
- [ ] **UAT-6 — HTTP Basic-auth:** Visit a Basic-auth-protected URL (a dev/staging site) with a matching 1Password login → picker appears → select → authenticates. Re-load after a wrong pick → confirm WebKit's own dialog appears (no loop).
- [ ] **UAT-7 — Regression:** Login username/password + TOTP fill still work; no overlay on ordinary text fields.

- [ ] **Step (after pass): commit a note** in the spec marking UAT complete.

---

## Self-Review

- **Spec coverage:** §4.1 sidecar → Task 1.2; §4.1 fill values → Task 1.2/1.3; §4.2 JS detection + multi-fill → Task 2.1; §4.3 Swift types/provider/service → Task 1.3; §4.3 suggestions/overlay/not-host-scoped → Slices 3–4; §5 Basic-auth → Slice 5; §3 vocabulary → Global Constraints + FieldPurpose; §7 testing → per-slice tests + Slice 6 UAT; §9 out-of-scope respected (fill-only, no SSH, 1Password-only, autocomplete+light-regex). All mapped.
- **Placeholder scan:** the only environment-derived values (real vault/item IDs in Task 1.1, exact field IDs) are gated by an explicit empirical discovery task (1.1) feeding `FIELD_SCHEMA.md`; no vague "handle errors"/"TBD" steps.
- **Type consistency:** `FieldPurpose`, `StructuredCategory`, `ProviderStructuredItem`, `PasswordBridgeField`, `PasswordMultiFillRequest`, `structured(from:account:)`, `structuredItems(_:)`, `fillValues(for:)`, `fillStructured(_:for:)`, `resolveSuggestions(..., structuredItems:)`, and the wire methods `listStructured`/`fillItem`/`fillFields` are used consistently across tasks.
- **Discovery-first honesty:** Task 1.1 empirically confirms the SDK field schema before extraction rather than hard-coding possibly-wrong field IDs; several Swift wiring points name a `grep` to locate the exact current call site rather than assuming it.
