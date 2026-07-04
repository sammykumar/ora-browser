package main

import "github.com/1password/onepassword-sdk-go"

// getAllBatchLimit is the maximum number of item IDs Items().GetAll accepts per call.
const getAllBatchLimit = 50

// chunkIDs splits ids into consecutive slices of at most size elements.
func chunkIDs(ids []string, size int) [][]string {
	if size <= 0 {
		return [][]string{ids}
	}
	var chunks [][]string
	for start := 0; start < len(ids); start += size {
		end := start + size
		if end > len(ids) {
			end = len(ids)
		}
		chunks = append(chunks, ids[start:end])
	}
	return chunks
}

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

// extractTOTP returns the current one-time password code from a fully-fetched item,
// if it has a TOTP field with an SDK-computed code.
func extractTOTP(item onepassword.Item) (string, bool) {
	for _, f := range item.Fields {
		if f.FieldType == onepassword.ItemFieldTypeTOTP {
			details := f.Details.OTP()
			if details != nil && details.Code != nil {
				return *details.Code, true
			}
		}
	}
	return "", false
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
