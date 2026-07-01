# Security

Evo is a personal, single-user macOS browser maintained by SK Productions LLC. There is no external security disclosure process.

## Local hygiene

- Never commit `.env`, signing credentials, private keys, notarization credentials, or other secret material.
- Sparkle auto-update is disabled — see [CLAUDE.md](CLAUDE.md). There is no appcast; `checkForUpdatesInBackground()` is a no-op.
- There is no signed-release or notarization pipeline yet. See [BUILD.md](BUILD.md) for the current local, unsigned build/test path.
