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
	return nil, nil // filled in Task 1.2
}
func (s *sdkClient) revealItem(ctx context.Context, vaultID, itemID string) (string, string, error) {
	return "", "", nil // filled in Task 1.2
}
func (s *sdkClient) totp(ctx context.Context, vaultID, itemID string) (string, error) {
	return "", nil // filled in Task 4.3
}
func (s *sdkClient) saveItem(ctx context.Context, p saveParams) (string, string, error) {
	return "", "", nil // filled in Task 3.1
}
