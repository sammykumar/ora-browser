package main

import (
	"testing"

	"github.com/1password/onepassword-sdk-go"
)

func loginItem() onepassword.Item {
	return onepassword.Item{
		ID: "i1", VaultID: "v1", Title: "GitHub",
		Websites: []onepassword.Website{{URL: "https://github.com", Label: "website"}},
		Fields: []onepassword.ItemField{
			{ID: "username", Title: "username", FieldType: onepassword.ItemFieldTypeText, Value: "octocat"},
			{ID: "password", Title: "password", FieldType: onepassword.ItemFieldTypeConcealed, Value: "s3cret"},
			{ID: "onetimepassword", Title: "one-time password", FieldType: onepassword.ItemFieldTypeTOTP, Value: "otpauth://totp/x"},
		},
	}
}

func TestItemToMetadata(t *testing.T) {
	item := loginItem()
	ov := onepassword.ItemOverview{ID: "i1", VaultID: "v1", Title: "GitHub", Websites: item.Websites}
	dto := itemToMetadata("v1", ov, item)
	if dto.Username != "octocat" {
		t.Fatalf("username = %q, want octocat", dto.Username)
	}
	if !dto.HasTotp {
		t.Fatalf("hasTotp should be true")
	}
	if len(dto.URLs) != 1 || dto.URLs[0] != "https://github.com" {
		t.Fatalf("urls = %v", dto.URLs)
	}
}

func TestExtractLoginNeverLeaksIntoMetadata(t *testing.T) {
	_, password := extractLogin(loginItem())
	if password != "s3cret" {
		t.Fatalf("extractLogin password = %q", password)
	}
	// Metadata must NOT carry the password:
	ov := onepassword.ItemOverview{ID: "i1", VaultID: "v1", Title: "GitHub"}
	dto := itemToMetadata("v1", ov, loginItem())
	if got, _ := any(dto).(itemDTO); got.Username == "s3cret" {
		t.Fatal("password leaked into metadata")
	}
}
