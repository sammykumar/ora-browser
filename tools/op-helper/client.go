package main

import (
	"context"

	"github.com/1password/onepassword-sdk-go"
)

type sdkClient struct {
	client *onepassword.Client
}

func newSDKClient(account, name, version string) (opClient, error) {
	c, err := onepassword.NewClient(context.Background(),
		onepassword.WithDesktopAppIntegration(account),
		onepassword.WithIntegrationInfo(name, version),
	)
	if err != nil {
		return nil, err
	}
	return &sdkClient{client: c}, nil
}

func (s *sdkClient) listVaults(ctx context.Context) ([]vaultDTO, error) {
	vaults, err := s.client.Vaults().List(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]vaultDTO, 0, len(vaults))
	for _, v := range vaults {
		out = append(out, vaultDTO{ID: v.ID, Title: v.Title})
	}
	return out, nil
}

func (s *sdkClient) listItems(ctx context.Context, vaultID string) ([]itemDTO, error) {
	overviews, err := s.client.Items().List(ctx, vaultID,
		onepassword.NewItemListFilterTypeVariantByState(
			&onepassword.ItemListFilterByStateInner{Active: true, Archived: false}))
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(overviews))
	byID := make(map[string]onepassword.ItemOverview, len(overviews))
	for _, ov := range overviews {
		if ov.Category != onepassword.ItemCategoryLogin {
			continue
		}
		ids = append(ids, ov.ID)
		byID[ov.ID] = ov
	}
	if len(ids) == 0 {
		return nil, nil
	}
	// Items().GetAll caps at 50 item IDs per call, so hydrate in chunks.
	out := make([]itemDTO, 0, len(ids))
	for _, chunk := range chunkIDs(ids, getAllBatchLimit) {
		batch, err := s.client.Items().GetAll(ctx, vaultID, chunk)
		if err != nil {
			return nil, err
		}
		for _, res := range batch.IndividualResponses {
			if res.Content == nil {
				continue
			}
			full := *res.Content
			out = append(out, itemToMetadata(vaultID, byID[full.ID], full))
		}
	}
	return out, nil
}

func (s *sdkClient) revealItem(ctx context.Context, vaultID, itemID string) (string, string, error) {
	item, err := s.client.Items().Get(ctx, vaultID, itemID)
	if err != nil {
		return "", "", err
	}
	u, p := extractLogin(item)
	return u, p, nil
}
func (s *sdkClient) totp(ctx context.Context, vaultID, itemID string) (string, error) {
	return "", nil // filled in Task 4.3
}
func (s *sdkClient) saveItem(ctx context.Context, p saveParams) (string, string, error) {
	if p.ItemID == "" {
		created, err := s.client.Items().Create(ctx, buildCreateParams(p))
		if err != nil {
			return "", "", err
		}
		return created.ID, created.VaultID, nil
	}
	item, err := s.client.Items().Get(ctx, p.VaultID, p.ItemID)
	if err != nil {
		return "", "", err
	}
	updated, err := s.client.Items().Put(ctx, applyUpdate(item, p.Username, p.Password))
	if err != nil {
		return "", "", err
	}
	return updated.ID, updated.VaultID, nil
}
