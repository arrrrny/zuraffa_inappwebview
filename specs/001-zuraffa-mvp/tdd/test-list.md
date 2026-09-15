# Test List — zuraffa_inappwebview MVP

| ID | Behavior | Package | Status |
|---|---|---|---|
| W1 | create → run → dispose drives the port in order | app | ✅ |
| W2 | double create → `already_created` | app | ✅ |
| W3 | ops before create → `not_created` | app | ✅ |
| W4 | double run → `already_running` | app | ✅ |
| W5 | dispose clears state; id reusable | app | ✅ |
| W6 | loadUrl forwards validated URL + headers | app | ✅ |
| W7 | currentUrl / evaluateJavascript / getHtml delegate | app | ✅ |
| W8 | cookies route to the shared store | app | ✅ |
| W9 | WebviewUri scheme validation | app | ✅ |
| W10 | WebviewSettings → channel args | app | ✅ |
| W11 | WebviewCookie channel round-trip | app | ✅ |
| W12–W14 | LoadUrl / EvaluateJavascript / SetCookie usecases | app | ✅ |
| W15 | unwired default → `port_not_wired` typed failures | app | ✅ |
| W16 | pre-registered port never overridden | app | ✅ |
| W17 | module registration equivalence | app | ✅ |
| WA1–WA6 | adapter: envelope mapping + typed native errors (per platform) | android/ios/macos | ✅ |
| — | envelope: timeout, typed passthrough, malformed payloads | platform | ✅ (scaffold suite) |

Counts: app 17 · platform 6 · android 6 · ios 6 · macos 6 = **41**.
