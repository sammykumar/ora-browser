# Deprecated WebKit implementation

The original Evo application used SwiftUI and WKWebView. It remains available
for historical behavior and visual reference at:

- Branch: `legacy/webkit`
- Tag: `webkit-final`
- Final revision: `c11a41981ba764397ce07fcdbe6ebf8f8f12a949`

The active product is Chromium-based. Do not port new functionality back to the
WebKit branch. If an old interaction is useful, document the behavior and
reimplement it against Chromium's current architecture.
