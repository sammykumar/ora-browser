# Broader 1Password autofill: cards, identities, HTTP Basic-auth — design

**Date:** 2026-07-05
**Status:** Design approved; ready for implementation planning.
**Relates to:** the 1Password integration (`2026-07-04-1password-integration-design.md`) and its Chrome-extension gap analysis. These are the non-passkey "autofill breadth" gaps. Passkeys are handled separately (`2026-07-05-passkey-support-design.md`). **SSH-key fill is explicitly dropped** — 1Password SSH keys are used by a local SSH agent for terminal git/ssh, not injected into web pages.

## 1. Goal & scope

Add three capabilities to Evo's existing 1Password autofill, matching the parts of the Chrome extension worth having for a single-user browser:

1. **Credit-card fill** — fill card fields on checkout forms from 1Password `CreditCard` items.
2. **Identity/address fill** — fill name/address/phone/email fields from 1Password `Identity` items.
3. **HTTP Basic-auth fill** — offer matching logins when a site issues an HTTP Basic/Digest auth challenge.

**Fill only** — no capturing/saving of new cards or identities. Cards and identities are **1Password-only** (the built-in Evo Keychain vault stores no such items). Basic-auth works with whichever provider is active.

Success:
- Focusing a card field on a real checkout (e.g. Stripe test form) shows an overlay listing the user's cards; selecting one fills number, expiry, CVV, and cardholder name across the form.
- Focusing an address/name field shows the user's identities; selecting one fills the address block.
- Visiting a Basic-auth-protected URL (e.g. a dev/staging site) offers matching 1Password logins and, on selection, authenticates without WebKit's raw dialog.

## 2. Non-negotiable constraints (carried from the existing integration)

- **Secrets discipline.** Metadata caches carry NO secrets. Card number, CVV, and Basic-auth passwords cross the wire **only at fill/submit time**, fetched on demand from the sidecar.
- **One sidecar process per 1Password account** (unchanged).
- **No new WebKit message channels unless registered** in `BrowserPageConfiguration.evoDefault` and handled in `BrowserPageDelegate` (we reuse the existing `passwordManager` channel).
- Follow existing patterns: `PasswordProvider` seam, `OpHelperProcess`/`OpHelperTransport`, `PasswordAutofillCoordinator`, toast-based errors.

## 3. Shared field-purpose vocabulary

Both the JS detector and the sidecar value-extraction agree on one string vocabulary so a detected field maps unambiguously to an item value. Defined once as a Swift enum `FieldPurpose: String` and mirrored by the JS token map and Go extraction.

**Credit card:** `cardholderName`, `cardNumber`, `expMonth`, `expYear`, `expDate` (combined MM/YY when a form has a single expiry field), `cvv`.
**Identity:** `givenName`, `familyName`, `fullName`, `addressLine1`, `addressLine2`, `city`, `state`, `postalCode`, `country`, `phone`, `email`, `organization`.

`autocomplete`-token → purpose mapping follows the WHATWG spec (e.g. `cc-number`→`cardNumber`, `cc-exp`→`expDate`, `cc-exp-month`→`expMonth`, `cc-csc`→`cvv`, `cc-name`→`cardholderName`, `street-address`/`address-line1`→`addressLine1`, `address-level2`→`city`, `address-level1`→`state`, `postal-code`→`postalCode`, `tel`→`phone`, `email`→`email`, `given-name`→`givenName`, `family-name`→`familyName`).

## 4. Structured autofill (cards + identities)

Cards and identities share one path; only the field set differs.

### 4.1 Go sidecar
- **`listStructured`** — returns `CreditCard` and `Identity` items as **metadata only**: `{id, vaultID, accountName, category, title, subtitle}`. `subtitle` is a non-secret display string: for cards, brand + last-4 (e.g. `Visa ····1234`) — last-4 is not sensitive and is what 1Password itself shows; for identities, the full name or primary email. **Never** the full PAN or CVV.
- **`fillItem`** (params: `itemID`, `vaultID`) — fetches the full item and returns a `{purpose: value}` map using the §3 vocabulary. This is the only call that returns card number / CVV. Card expiry is normalized: 1Password stores an expiry; the sidecar emits `expMonth`+`expYear` (zero-padded month, 4-digit year) and a combined `expDate` (`MM/YY`) so JS can fill whichever field shape the form has.
- Extraction reads 1Password `ItemField`s by their category-specific purpose/field IDs (mirrors `extractLogin`/`extractTOTP` in `itemmap.go`). New file `structured.go` + tests in `structured_test.go`.

### 4.2 JS bridge (`password-manager.js`)
- Extend `fieldKindFor` to return `creditCard` or `identity` for card/address inputs, detected by (a) standard `autocomplete` tokens (primary) and (b) a **light** `name`/`id`/placeholder regex fallback for common un-annotated fields (e.g. `/card.?number|cardnum|ccnum/i`, `/(^|[^a-z])cvv|cvc|csc([^a-z]|$)/i`, `/postal|zip/i`). Accepts misses on exotic/obfuscated forms as a known limitation.
- On focus of a card/identity field, emit a focus payload that includes the **whole detected group**: an array of `{fieldID, purpose}` for every sibling fillable field in the same form, plus the group kind (`creditCard`/`identity`). The form is scoped to the focused field's enclosing `<form>` (or nearest common container if no form).
- New **multi-field fill** request handler: given `[{fieldID, value}]`, fill each field (reusing the existing `fillField` value-setter + input/change events). One selection fills the entire card/address block.

### 4.3 Swift
- New metadata type `ProviderStructuredItem { id, ref: ProviderItemRef, category: StructuredCategory, title, subtitle }` where `StructuredCategory` is `.creditCard | .identity`.
- Two new `PasswordProvider` methods:
  - `func structuredItems(_ category: StructuredCategory) async -> [ProviderStructuredItem]`
  - `func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String]`
  Implemented by `OnePasswordProvider` (calls the new sidecar methods); `EvoPasswordProvider` returns `[]` / throws unsupported.
- New `PasswordAutofillSuggestion` cases `.fillCard(ProviderStructuredItem)` and `.fillIdentity(ProviderStructuredItem)`, rendered as overlay rows (icon + title + subtitle).
- `PasswordAutofillCoordinator.resolveSuggestions` gains: when the focus `fieldKind` is `creditCard`/`identity`, surface the matching category's items. **Not host-scoped** — return *all* items of that category (a card/identity is valid on any site). Login/OTP/email behavior is unchanged.
- On selection: `fillValues(for:)` → build `[{fieldID, value}]` by matching each detected field's `purpose` to the returned map → send the multi-field fill request. Missing purposes are simply skipped (partial forms fill what they can).

## 5. HTTP Basic-auth fill

Independent of the JS bridge and the on-page overlay.

- Hook the existing `webView(_:didReceive challenge:completionHandler:)` at `BrowserPage.swift:352`.
- Branch **only** when `challenge.protectionSpace.authenticationMethod` is one of `NSURLAuthenticationMethodHTTPBasic`, `NSURLAuthenticationMethodHTTPDigest`, `NSURLAuthenticationMethodNTLM`. Every other challenge (server trust, client certificate) keeps its **current** behavior — this is a strict addition, not a rewrite.
- On a Basic/Digest/NTLM challenge: look up logins for `challenge.protectionSpace.host` via the active provider's existing `credentials(for:)`. Guard against repeated failures with `challenge.previousFailureCount` (if > 0, fall through to default so the user isn't looped).
  - **Matches found:** present a lightweight credential picker (a SwiftUI sheet listing `title` + `displayUsername`). On pick → `reveal` → `completionHandler(.useCredential, URLCredential(user:password:persistence:.forSession))`. On cancel → `completionHandler(.performDefaultHandling, nil)`.
  - **No matches:** `completionHandler(.performDefaultHandling, nil)` (WebKit shows its own dialog).
- Respects private windows (uses that window's provider/profile as today).

## 6. Error handling

- Reuse the sidecar error mapping (`locked`, `timeout`, `notFound`, `connectionDropped`, …) and the existing toast surface.
- A failed `fillValues`/`reveal` shows a toast and fills nothing (never a partial/garbage fill).
- Locked vault on a card/identity focus surfaces the same state the login path uses.

## 7. Testing

- **Go:** `structured_test.go` — extraction for a `CreditCard` item (number/exp/cvv/cardholder → correct purposes; expiry normalization) and an `Identity` item; and a leak test asserting no card number/CVV appears in serialized `listStructured` metadata (mirrors `TestExtractLoginNeverLeaksIntoMetadata`).
- **Swift:** decode tests for the new card/identity focus payloads; `resolveSuggestions` tests asserting a card-field focus surfaces `.fillCard` rows for all cards and is NOT host-filtered; a Basic-auth picker view-model test for match/no-match/previousFailureCount branching (mirrors `OneTimeCodeDecodeTests` style).
- **Manual UAT** (OS/page-brokered, like existing passwords UAT): real checkout card fill, address fill, Basic-auth on a protected dev URL, and a regression pass that logins/TOTP still fill.

## 8. Slicing (for the implementation plan)

1. **Sidecar + provider plumbing** — `listStructured` + `fillItem` (Go, tested) and the two `PasswordProvider` methods + types (Swift, tested). No UI.
2. **JS detection + multi-field fill** — `fieldKindFor`/group detection + the multi-field fill handler (focus-payload decode tests).
3. **Credit-card overlay + fill wiring** — suggestion case, overlay row, `resolveSuggestions`, selection→fill.
4. **Identity overlay + fill wiring** — reuses Slice 3 infra for the identity field set.
5. **HTTP Basic-auth fill** — challenge-handler branch + picker (independent; can land any time after Slice 0).

## 9. Out of scope (YAGNI)

- Capturing/saving **new** cards or identities (fill-only v1).
- SSH-key fill (dropped — not a browser operation).
- A full label/proximity heuristics engine matching 1Password's detector; v1 uses `autocomplete` tokens + light regex fallback and accepts reduced robustness on exotic forms.
- Card/identity fill from the built-in Evo Keychain vault (1Password-only).
