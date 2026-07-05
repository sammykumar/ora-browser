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
			{ID: "type", Title: "type", FieldType: onepassword.ItemFieldTypeCreditCardType, Value: "Visa"},
			// Card number's last 4 ("9999") and the CVV ("456") are deliberately chosen with
			// no digit-substring overlap, so the leak assertion below can't pass by accident.
			{ID: "ccnum", Title: "number", FieldType: onepassword.ItemFieldTypeCreditCardNumber, Value: "4111111111119999"},
			{ID: "cvv", Title: "verification number", FieldType: onepassword.ItemFieldTypeConcealed, Value: "456"},
			{ID: "expiry", Title: "expiry date", FieldType: onepassword.ItemFieldTypeMonthYear, Value: "202809"},
		},
	}
}

func identityItem() onepassword.Item {
	return onepassword.Item{
		ID: "id1", VaultID: "v1", Title: "Sam's Identity", Category: onepassword.ItemCategoryIdentity,
		Fields: []onepassword.ItemField{
			{ID: "firstname", Title: "first name", FieldType: onepassword.ItemFieldTypeText, Value: "Sam"},
			{ID: "lastname", Title: "last name", FieldType: onepassword.ItemFieldTypeText, Value: "Kumar"},
			{ID: "company", Title: "company", FieldType: onepassword.ItemFieldTypeText, Value: "SK Productions"},
			{ID: "email", Title: "email", FieldType: onepassword.ItemFieldTypeText, Value: "sam@skproductions.llc"},
			{ID: "defphone", Title: "default phone", FieldType: onepassword.ItemFieldTypeText, Value: "555-0100"},
			{
				ID: "address", Title: "address", FieldType: onepassword.ItemFieldTypeAddress,
				Details: addressDetails(&onepassword.AddressFieldDetails{
					Street: "1 Infinite Loop", City: "Cupertino", State: "CA", Zip: "95014", Country: "US",
				}),
			},
		},
	}
}

// addressDetails builds an *ItemFieldDetails wrapping address components, mirroring
// what the SDK constructs internally when unmarshalling a real item.
func addressDetails(addr *onepassword.AddressFieldDetails) *onepassword.ItemFieldDetails {
	d := onepassword.NewItemFieldDetailsTypeVariantAddress(addr)
	return &d
}

func TestCardToStructuredHasNoSecretsInSubtitle(t *testing.T) {
	dto := itemToStructured("v1", cardItem())
	if dto.Category != "creditCard" {
		t.Fatalf("category = %q", dto.Category)
	}
	blob, _ := json.Marshal(dto)
	if strings.Contains(string(blob), "4111111111119999") || strings.Contains(string(blob), "456") {
		t.Fatalf("secret leaked into metadata: %s", blob)
	}
	if !strings.Contains(dto.Subtitle, "9999") { // last-4 is allowed and expected
		t.Fatalf("subtitle should show last-4, got %q", dto.Subtitle)
	}
}

func TestExtractFillValuesCard(t *testing.T) {
	v := extractFillValues(cardItem())
	if v["cardNumber"] != "4111111111119999" {
		t.Fatalf("cardNumber = %q", v["cardNumber"])
	}
	if v["cvv"] != "456" {
		t.Fatalf("cvv = %q", v["cvv"])
	}
	if v["expMonth"] != "09" || v["expYear"] != "2028" || v["expDate"] != "09/28" {
		t.Fatalf("expiry map wrong: %q %q %q", v["expMonth"], v["expYear"], v["expDate"])
	}
	if v["cardholderName"] != "Sam Kumar" {
		t.Fatalf("cardholderName = %q", v["cardholderName"])
	}
}

func TestIdentityToStructuredHasNoSecretsAndUsesFullName(t *testing.T) {
	dto := itemToStructured("v1", identityItem())
	if dto.Category != "identity" {
		t.Fatalf("category = %q", dto.Category)
	}
	if dto.Subtitle != "Sam Kumar" {
		t.Fatalf("subtitle = %q, want %q", dto.Subtitle, "Sam Kumar")
	}
	blob, _ := json.Marshal(dto)
	if strings.Contains(string(blob), "sam@skproductions.llc") || strings.Contains(string(blob), "555-0100") {
		t.Fatalf("identity PII leaked into metadata: %s", blob)
	}
}

func TestExtractFillValuesIdentity(t *testing.T) {
	v := extractFillValues(identityItem())
	if v["givenName"] != "Sam" {
		t.Fatalf("givenName = %q", v["givenName"])
	}
	if v["familyName"] != "Kumar" {
		t.Fatalf("familyName = %q", v["familyName"])
	}
	if v["organization"] != "SK Productions" {
		t.Fatalf("organization = %q", v["organization"])
	}
	if v["email"] != "sam@skproductions.llc" {
		t.Fatalf("email = %q", v["email"])
	}
	if v["phone"] != "555-0100" {
		t.Fatalf("phone = %q", v["phone"])
	}
	if v["addressLine1"] != "1 Infinite Loop" {
		t.Fatalf("addressLine1 = %q", v["addressLine1"])
	}
	if v["city"] != "Cupertino" {
		t.Fatalf("city = %q", v["city"])
	}
	if v["state"] != "CA" {
		t.Fatalf("state = %q", v["state"])
	}
	if v["postalCode"] != "95014" {
		t.Fatalf("postalCode = %q", v["postalCode"])
	}
	if v["country"] != "US" {
		t.Fatalf("country = %q", v["country"])
	}
	if v["fullName"] != "Sam Kumar" {
		t.Fatalf("fullName = %q, want %q", v["fullName"], "Sam Kumar")
	}
}

// TestExtractFillValuesTitleFallback ensures a field whose real 1Password ID doesn't
// match FIELD_SCHEMA.md's assumed defaults still maps via a title-keyword fallback,
// so mapTextField degrades gracefully instead of silently dropping the value.
func TestExtractFillValuesTitleFallback(t *testing.T) {
	item := onepassword.Item{
		ID: "id2", VaultID: "v1", Title: "Fallback Identity", Category: onepassword.ItemCategoryIdentity,
		Fields: []onepassword.ItemField{
			{ID: "f1", Title: "First Name", FieldType: onepassword.ItemFieldTypeText, Value: "Ada"},
			{ID: "f2", Title: "Last Name", FieldType: onepassword.ItemFieldTypeText, Value: "Lovelace"},
			{ID: "f3", Title: "Organization", FieldType: onepassword.ItemFieldTypeText, Value: "Analytical Engines Inc"},
			{ID: "f4", Title: "Email Address", FieldType: onepassword.ItemFieldTypeText, Value: "ada@example.com"},
			{ID: "f5", Title: "Mobile Phone", FieldType: onepassword.ItemFieldTypeText, Value: "555-0199"},
		},
	}
	v := extractFillValues(item)
	if v["givenName"] != "Ada" {
		t.Fatalf("givenName = %q", v["givenName"])
	}
	if v["familyName"] != "Lovelace" {
		t.Fatalf("familyName = %q", v["familyName"])
	}
	if v["organization"] != "Analytical Engines Inc" {
		t.Fatalf("organization = %q", v["organization"])
	}
	if v["email"] != "ada@example.com" {
		t.Fatalf("email = %q", v["email"])
	}
	if v["phone"] != "555-0199" {
		t.Fatalf("phone = %q", v["phone"])
	}
	if v["fullName"] != "Ada Lovelace" {
		t.Fatalf("fullName = %q", v["fullName"])
	}
}

// TestExtractFillValuesCVVCaseInsensitive ensures the CVV field-ID match is
// case-insensitive, matching mapTextField's lower-casing convention.
func TestExtractFillValuesCVVCaseInsensitive(t *testing.T) {
	item := onepassword.Item{
		ID: "c2", VaultID: "v1", Title: "Uppercase CVV Card", Category: onepassword.ItemCategoryCreditCard,
		Fields: []onepassword.ItemField{
			{ID: "CVV", Title: "security code", FieldType: onepassword.ItemFieldTypeConcealed, Value: "789"},
		},
	}
	v := extractFillValues(item)
	if v["cvv"] != "789" {
		t.Fatalf("cvv = %q, want %q (case-insensitive ID match)", v["cvv"], "789")
	}
}
