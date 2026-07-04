package main

import "strings"

func mapSDKError(err error) (code, message string) {
	if err == nil {
		return "", ""
	}
	m := err.Error()
	switch {
	case strings.Contains(m, "notFound"):
		return "notFound", m
	case strings.Contains(m, "desktop application not found"):
		return "appMissing", m
	case strings.Contains(m, "channel is closed"):
		return "channelClosed", m
	case strings.Contains(m, "unexpectedly dropped"):
		return "connectionDropped", m
	case strings.Contains(m, "IncorrectItemVersion"):
		return "versionConflict", m
	default:
		return "internal", m
	}
}
