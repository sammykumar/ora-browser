package main

import (
	"errors"
	"testing"
)

func TestMapSDKError(t *testing.T) {
	cases := []struct {
		in   error
		code string
	}{
		{errors.New("1Password desktop application not found"), "appMissing"},
		{errors.New("desktop app connection channel is closed. Make sure Settings > Developer"), "channelClosed"},
		{errors.New("connection was unexpectedly dropped by the desktop app"), "connectionDropped"},
		{errors.New("itemStatusIncorrectItemVersion"), "versionConflict"},
		{errors.New("some other thing"), "internal"},
	}
	for _, c := range cases {
		code, msg := mapSDKError(c.in)
		if code != c.code {
			t.Errorf("mapSDKError(%q) code = %q, want %q", c.in, code, c.code)
		}
		if msg == "" {
			t.Errorf("mapSDKError(%q) message empty", c.in)
		}
	}
	if code, _ := mapSDKError(nil); code != "" {
		t.Errorf("nil error should map to empty code, got %q", code)
	}
}
