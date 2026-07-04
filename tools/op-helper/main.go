package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"
)

type opClient interface {
	listVaults(ctx context.Context) ([]vaultDTO, error)
	listItems(ctx context.Context, vaultID string) ([]itemDTO, error)
	revealItem(ctx context.Context, vaultID, itemID string) (username, password string, err error)
	totp(ctx context.Context, vaultID, itemID string) (string, error)
	saveItem(ctx context.Context, p saveParams) (itemID, vaultID string, err error)
}

func handle(ctx context.Context, c opClient, req request) response {
	switch req.Method {
	case "status":
		vaults, err := c.listVaults(ctx)
		if err != nil {
			code, msg := mapSDKError(err)
			return fail(req.ID, code, msg)
		}
		state := "ready"
		return ok(req.ID, map[string]interface{}{"state": state, "vaultCount": len(vaults)})
	case "listItems":
		items, err := gatherItems(ctx, c)
		if err != nil {
			code, msg := mapSDKError(err)
			return fail(req.ID, code, msg)
		}
		return ok(req.ID, map[string]interface{}{"items": items})
	case "reveal":
		vaultID, _ := req.Params["vaultId"].(string)
		itemID, _ := req.Params["itemId"].(string)
		u, p, err := c.revealItem(ctx, vaultID, itemID)
		if err != nil {
			code, msg := mapSDKError(err)
			return fail(req.ID, code, msg)
		}
		return ok(req.ID, map[string]interface{}{"username": u, "password": p})
	default:
		return fail(req.ID, "internal", "unknown method: "+req.Method)
	}
}

// gatherItems lists every vault's active items and hydrates metadata; NEVER returns secrets.
func gatherItems(ctx context.Context, c opClient) ([]itemDTO, error) {
	vaults, err := c.listVaults(ctx)
	if err != nil {
		return nil, err
	}
	var out []itemDTO
	for _, v := range vaults {
		items, err := c.listItems(ctx, v.ID)
		if err != nil {
			return nil, err
		}
		out = append(out, items...)
	}
	return out, nil
}

func main() {
	account := flag.String("account", "", "1Password account name or UUID")
	name := flag.String("integration-name", "Evo", "integration name")
	version := flag.String("integration-version", "0.0.0", "integration version")
	flag.Parse()
	if *account == "" {
		fmt.Fprintln(os.Stderr, "error: --account is required")
		os.Exit(2)
	}

	client, err := newSDKClient(*account, *name, *version)
	if err != nil {
		// Emit a single error line so Evo can surface a status, then exit.
		code, msg := mapSDKError(err)
		line, _ := json.Marshal(fail("", code, msg))
		fmt.Println(string(line))
		os.Exit(1)
	}

	out := bufio.NewWriter(os.Stdout)
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
	for scanner.Scan() {
		var req request
		if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
			continue // ignore malformed lines
		}
		resp := runWithWatchdog(client, req)
		line, _ := json.Marshal(resp)
		fmt.Fprintln(out, string(line))
		out.Flush()
	}
}

// runWithWatchdog wraps each request in a ctx-independent timer, because the SDK's
// lock-hang bug (#266) ignores context deadlines. On trip it emits a timeout error
// and exits so Evo respawns.
func runWithWatchdog(c opClient, req request) response {
	done := make(chan response, 1)
	go func() { done <- handle(context.Background(), c, req) }()
	select {
	case resp := <-done:
		return resp
	case <-time.After(20 * time.Second):
		line, _ := json.Marshal(fail(req.ID, "timeout", "1Password request timed out (vault may be locked)"))
		fmt.Println(string(line))
		os.Exit(1)
		return response{} // unreachable
	}
}
