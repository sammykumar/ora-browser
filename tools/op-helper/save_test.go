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
		},
	}
	updated := applyUpdate(item, "new", "newpass")
	var user, pass string
	for _, f := range updated.Fields {
		if f.FieldType == onepassword.ItemFieldTypeText {
			user = f.Value
		}
		if f.FieldType == onepassword.ItemFieldTypeConcealed {
			pass = f.Value
		}
	}
	if user != "new" || pass != "newpass" {
		t.Fatalf("update failed: user=%q pass=%q", user, pass)
	}
}
