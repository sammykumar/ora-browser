package main

// Wire protocol (NDJSON, one object per line). Account is implicit (bound at spawn).
type request struct {
	ID     string                 `json:"id"`
	Method string                 `json:"method"`
	Params map[string]interface{} `json:"params"`
}

type response struct {
	ID     string      `json:"id"`
	OK     bool        `json:"ok"`
	Result interface{} `json:"result,omitempty"`
	Error  *wireError  `json:"error,omitempty"`
}

type wireError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func ok(id string, result interface{}) response { return response{ID: id, OK: true, Result: result} }
func fail(id, code, msg string) response {
	return response{ID: id, OK: false, Error: &wireError{Code: code, Message: msg}}
}

// DTOs used by the client seam and by the pure helpers.
type vaultDTO struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type itemDTO struct {
	ID       string   `json:"id"`
	VaultID  string   `json:"vaultId"`
	Title    string   `json:"title"`
	Username string   `json:"username"`
	URLs     []string `json:"urls"`
	HasTotp  bool     `json:"hasTotp"`
}

// structuredDTO is secret-free metadata for a CreditCard or Identity item.
type structuredDTO struct {
	ID       string `json:"id"`
	VaultID  string `json:"vaultId"`
	Category string `json:"category"` // "creditCard" | "identity"
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"` // e.g. "Visa ····1234" or "Sam Kumar" — NEVER full PAN/CVV
}

type saveParams struct {
	VaultID  string
	ItemID   string
	Title    string
	URL      string
	Username string
	Password string
}

// str reads a string param out of a request's params map, defaulting to "" for
// missing or non-string values.
func str(m map[string]interface{}, k string) string {
	v, _ := m[k].(string)
	return v
}
