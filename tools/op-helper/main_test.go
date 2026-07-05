package main

import (
	"context"
	"testing"
)

// fakeClient implements opClient for tests (no DesktopAuth).
type fakeClient struct {
	vaults     []vaultDTO
	items      map[string][]itemDTO       // vaultID -> items
	structured map[string][]structuredDTO // vaultID -> structured items
	revealFn   func(vaultID, itemID string) (string, string, error)
	fillFn     func(vaultID, itemID string) (map[string]string, error)
}

func (f *fakeClient) listVaults(_ context.Context) ([]vaultDTO, error) { return f.vaults, nil }
func (f *fakeClient) listItems(_ context.Context, vaultID string) ([]itemDTO, error) {
	return f.items[vaultID], nil
}
func (f *fakeClient) revealItem(_ context.Context, vaultID, itemID string) (string, string, error) {
	return f.revealFn(vaultID, itemID)
}
func (f *fakeClient) totp(_ context.Context, vaultID, itemID string) (string, error) { return "", nil }
func (f *fakeClient) saveItem(_ context.Context, p saveParams) (string, string, error) {
	return "new-id", p.VaultID, nil
}
func (f *fakeClient) listStructured(_ context.Context, vaultID string) ([]structuredDTO, error) {
	return f.structured[vaultID], nil
}
func (f *fakeClient) fillItem(_ context.Context, vaultID, itemID string) (map[string]string, error) {
	if f.fillFn == nil {
		return map[string]string{}, nil
	}
	return f.fillFn(vaultID, itemID)
}

func TestHandleStatus(t *testing.T) {
	c := &fakeClient{vaults: []vaultDTO{{ID: "v1", Title: "Personal"}}}
	resp := handle(context.Background(), c, request{ID: "1", Method: "status"})
	if !resp.OK {
		t.Fatalf("status should succeed, got error %+v", resp.Error)
	}
	if resp.ID != "1" {
		t.Fatalf("response id mismatch: %q", resp.ID)
	}
}

func TestHandleUnknownMethod(t *testing.T) {
	resp := handle(context.Background(), &fakeClient{}, request{ID: "2", Method: "bogus"})
	if resp.OK || resp.Error == nil || resp.Error.Code != "internal" {
		t.Fatalf("unknown method should fail with internal, got %+v", resp)
	}
}

func TestHandleListStructuredGathersAcrossVaults(t *testing.T) {
	c := &fakeClient{
		vaults: []vaultDTO{{ID: "v1", Title: "Personal"}, {ID: "v2", Title: "Work"}},
		structured: map[string][]structuredDTO{
			"v1": {{ID: "c1", VaultID: "v1", Category: "creditCard", Title: "Visa", Subtitle: "Visa ····9999"}},
			"v2": {{ID: "id1", VaultID: "v2", Category: "identity", Title: "Sam", Subtitle: "Sam Kumar"}},
		},
	}
	resp := handle(context.Background(), c, request{ID: "3", Method: "listStructured"})
	if !resp.OK {
		t.Fatalf("listStructured should succeed, got error %+v", resp.Error)
	}
	result, ok := resp.Result.(map[string]interface{})
	if !ok {
		t.Fatalf("result has unexpected shape: %#v", resp.Result)
	}
	items, ok := result["items"].([]structuredDTO)
	if !ok || len(items) != 2 {
		t.Fatalf("expected 2 gathered structured items, got %#v", result["items"])
	}
}

func TestHandleFillItemReturnsValues(t *testing.T) {
	c := &fakeClient{
		fillFn: func(vaultID, itemID string) (map[string]string, error) {
			if vaultID != "v1" || itemID != "c1" {
				t.Fatalf("unexpected params: vault=%q item=%q", vaultID, itemID)
			}
			return map[string]string{"cardNumber": "4111111111119999"}, nil
		},
	}
	resp := handle(context.Background(), c, request{
		ID: "4", Method: "fillItem",
		Params: map[string]interface{}{"vaultId": "v1", "itemId": "c1"},
	})
	if !resp.OK {
		t.Fatalf("fillItem should succeed, got error %+v", resp.Error)
	}
	result, ok := resp.Result.(map[string]interface{})
	if !ok {
		t.Fatalf("result has unexpected shape: %#v", resp.Result)
	}
	values, ok := result["values"].(map[string]string)
	if !ok || values["cardNumber"] != "4111111111119999" {
		t.Fatalf("values = %#v", result["values"])
	}
}
