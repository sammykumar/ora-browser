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

type saveParams struct {
	VaultID  string
	ItemID   string
	Title    string
	URL      string
	Username string
	Password string
}
