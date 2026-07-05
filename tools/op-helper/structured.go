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
		case onepassword.ItemFieldTypeEmail:
			if out["email"] == "" {
				out["email"] = f.Value
			}
		case onepassword.ItemFieldTypePhone:
			if out["phone"] == "" {
				out["phone"] = f.Value
			}
		case onepassword.ItemFieldTypeAddress:
			mapAddressField(f, out)
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

// mapAddressField reads the SDK's single structured address field (street/city/state/
// zip/country — there is no separate line-2) into the shared address purposes.
// See FIELD_SCHEMA.md for why addressLine2 is never populated.
func mapAddressField(f onepassword.ItemField, out map[string]string) {
	if f.Details == nil {
		return
	}
	addr := f.Details.Address()
	if addr == nil {
		return
	}
	if addr.Street != "" {
		out["addressLine1"] = addr.Street
	}
	if addr.City != "" {
		out["city"] = addr.City
	}
	if addr.State != "" {
		out["state"] = addr.State
	}
	if addr.Zip != "" {
		out["postalCode"] = addr.Zip
	}
	if addr.Country != "" {
		out["country"] = addr.Country
	}
}
