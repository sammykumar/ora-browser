package main

import (
	"testing"

	"github.com/1password/onepassword-sdk-go"
)

func TestBuildCreateParams(t *testing.T) {
	p := saveParams{VaultID: "v1", Title: "example.com", URL: "https://example.com", Username: "sam", Password: "p@ss"}
	params := buildCreateParams(p)
	if params.Category != onepassword.ItemCategoryLogin || params.VaultID != "v1" {
		t.Fatalf("bad params: %+v", params)
	}
	if len(params.Websites) != 1 || params.Websites[0].AutofillBehavior != onepassword.AutofillBehaviorAnywhereOnWebsite {
		t.Fatalf("website not set: %+v", params.Websites)
	}
	var user, pass string
	for _, f := range params.Fields {
		if f.FieldType == onepassword.ItemFieldTypeText {
			user = f.Value
		}
		if f.FieldType == onepassword.ItemFieldTypeConcealed {
			pass = f.Value
		}
	}
	if user != "sam" || pass != "p@ss" {
		t.Fatalf("fields wrong: user=%q pass=%q", user, pass)
	}
}

func TestApplyUpdate(t *testing.T) {
	item := onepassword.Item{
		ID: "i1", VaultID: "v1",
		Fields: []onepassword.ItemField{
			{ID: "username", Title: "username", FieldType: onepassword.ItemFieldTypeText, Value: "old"},
			{ID: "password", Title: "password", FieldType: onepassword.ItemFieldTypeConcealed, Value: "oldpass"},
			{ID: "onetimepassword", Title: "one-time password", FieldType: onepassword.ItemFieldTypeTOTP, Value: "otpauth://totp/x?secret=abc"},
		},
	}
	updated := applyUpdate(item, "new", "newpass")
	var user, pass string
	var totp *onepassword.ItemField
	for i, f := range updated.Fields {
		if f.FieldType == onepassword.ItemFieldTypeText {
			user = f.Value
		}
		if f.FieldType == onepassword.ItemFieldTypeConcealed {
			pass = f.Value
		}
		if f.FieldType == onepassword.ItemFieldTypeTOTP {
			totp = &updated.Fields[i]
		}
	}
	if user != "new" || pass != "newpass" {
		t.Fatalf("update failed: user=%q pass=%q", user, pass)
	}
	if len(updated.Fields) != 3 {
		t.Fatalf("expected 3 fields (nothing dropped), got %d: %+v", len(updated.Fields), updated.Fields)
	}
	if totp == nil {
		t.Fatalf("TOTP field was dropped by applyUpdate")
	}
	if totp.Value != "otpauth://totp/x?secret=abc" {
		t.Fatalf("TOTP field value was mutated: got %q", totp.Value)
	}
	if totp.FieldType != onepassword.ItemFieldTypeTOTP {
		t.Fatalf("TOTP field type changed: got %v", totp.FieldType)
	}
}
