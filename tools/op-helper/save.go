package main

import "github.com/1password/onepassword-sdk-go"

// buildCreateParams builds the SDK create params for a new Login item. Pure — no I/O.
func buildCreateParams(p saveParams) onepassword.ItemCreateParams {
	return onepassword.ItemCreateParams{
		Category: onepassword.ItemCategoryLogin,
		VaultID:  p.VaultID,
		Title:    p.Title,
		Fields: []onepassword.ItemField{
			{ID: "username", Title: "username", FieldType: onepassword.ItemFieldTypeText, Value: p.Username},
			{ID: "password", Title: "password", FieldType: onepassword.ItemFieldTypeConcealed, Value: p.Password},
		},
		Websites: []onepassword.Website{
			{URL: p.URL, Label: "website", AutofillBehavior: onepassword.AutofillBehaviorAnywhereOnWebsite},
		},
	}
}

// applyUpdate mutates the username/password field values on an existing item in place
// and returns it, leaving all other fields untouched. Pure — no I/O.
func applyUpdate(item onepassword.Item, username, password string) onepassword.Item {
	for i := range item.Fields {
		switch item.Fields[i].FieldType {
		case onepassword.ItemFieldTypeText:
			if item.Fields[i].ID == "username" || item.Fields[i].Title == "username" {
				item.Fields[i].Value = username
			}
		case onepassword.ItemFieldTypeConcealed:
			if item.Fields[i].ID == "password" || item.Fields[i].Title == "password" {
				item.Fields[i].Value = password
			}
		}
	}
	return item
}
