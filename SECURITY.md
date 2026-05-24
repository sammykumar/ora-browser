# Security

Evo is a personal, single-user fork of [the-ora/browser](https://github.com/the-ora/browser) maintained by SK Productions LLC. There is no external security disclosure process — for issues in the underlying open-source browser, report upstream.

## Local hygiene

- Never commit `.env`, signing credentials, private keys, notarization credentials, or other secret material.
- Sparkle auto-update is disabled in this fork — see [FORK_PATCHES.md](FORK_PATCHES.md). The upstream `ora_public_key.pem` and `appcast.xml` files in the repo root are leftover Ora artifacts and are not used.
- The upstream release scripts (`scripts/build.sh`, `scripts/publish.sh`, `scripts/release.sh`) still reference the old `com.orabrowser.app` bundle ID and the Ora team signing identity — **not safe to run as-is** on this fork. See [BUILD.md](BUILD.md).
