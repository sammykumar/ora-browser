package main

import (
	"testing"

	"github.com/1password/onepassword-sdk-go"
)

func TestExtractTOTP(t *testing.T) {
	plain := onepassword.Item{Fields: []onepassword.ItemField{{FieldType: onepassword.ItemFieldTypeText, Value: "u"}}}
	if _, ok := extractTOTP(plain); ok {
		t.Fatal("no TOTP field should return ok=false")
	}
}

func TestExtractTOTPNilDetailsDoesNotPanic(t *testing.T) {
	item := onepassword.Item{Fields: []onepassword.ItemField{
		{FieldType: onepassword.ItemFieldTypeTOTP, Details: nil},
	}}
	code, ok := extractTOTP(item)
	if ok || code != "" {
		t.Fatalf("nil Details should yield (\"\", false), got (%q, %v)", code, ok)
	}
}

func TestExtractTOTPReturnsCode(t *testing.T) {
	code := "123456"
	details := onepassword.NewItemFieldDetailsTypeVariantOTP(&onepassword.OTPFieldDetails{Code: &code})
	item := onepassword.Item{Fields: []onepassword.ItemField{
		{FieldType: onepassword.ItemFieldTypeTOTP, Details: &details},
	}}
	got, ok := extractTOTP(item)
	if !ok || got != "123456" {
		t.Fatalf("expected (\"123456\", true), got (%q, %v)", got, ok)
	}
}
