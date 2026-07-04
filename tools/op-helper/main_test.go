package main

import (
	"context"
	"testing"
)

// fakeClient implements opClient for tests (no DesktopAuth).
type fakeClient struct {
	vaults   []vaultDTO
	items    map[string][]itemDTO // vaultID -> items
	revealFn func(vaultID, itemID string) (string, string, error)
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
