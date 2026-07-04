package main

import "github.com/1password/onepassword-sdk-go"

// itemToMetadata builds the metadata DTO. It reads the username + hasTotp from the
// full item but NEVER copies the password.
func itemToMetadata(vaultID string, ov onepassword.ItemOverview, full onepassword.Item) itemDTO {
	dto := itemDTO{ID: ov.ID, VaultID: vaultID, Title: ov.Title}
	for _, w := range ov.Websites {
		if w.URL != "" {
			dto.URLs = append(dto.URLs, w.URL)
		}
	}
	for _, f := range full.Fields {
		switch f.FieldType {
		case onepassword.ItemFieldTypeText:
			if f.ID == "username" || f.Title == "username" {
				dto.Username = f.Value
			}
		case onepassword.ItemFieldTypeTOTP:
			dto.HasTotp = true
		}
	}
	return dto
}

// extractLogin returns the username and password from a fully-fetched item.
func extractLogin(item onepassword.Item) (username, password string) {
	for _, f := range item.Fields {
		switch f.FieldType {
		case onepassword.ItemFieldTypeText:
			if f.ID == "username" || f.Title == "username" {
				username = f.Value
			}
		case onepassword.ItemFieldTypeConcealed:
			if f.ID == "password" || f.Title == "password" {
				password = f.Value
			}
		}
	}
	return username, password
}
