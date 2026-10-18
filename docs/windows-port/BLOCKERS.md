# Blockers

Items a milestone could not finish within four review rounds (TASK.md §5.5): symptom, what was tried, suggestion.

## B-001 — M4 not approved after four rounds: two Windows implementations without tests (2026-10-18)

- **Symptom.** M4 review round 4 (`reports/M4-review-4.md`, on `4cdf931`) returned CHANGES_REQUESTED with two BLOCKING
  items, both new in that round. (1) `WindowsHTTP.send` (`Platform/Windows/ProviderHTTP+Windows.swift`), the WinHTTP
  transport of every Windows quota request (D-014), has no Windows test: provider tests replace the transport, so none
  of its rules (no redirect, no cookie, no WinHTTP authentication, body limit, timeout, fail closed) runs on Windows.
  (2) `WindowsCredentials.genericSecret` (Credential Manager, Copilot's `gh:github.com:`) has no test. All gates of the
  same round passed (`reports/M4-tests-4.md`: TESTS ALL_PASS; CI runs 39047601254 and 39047601576), and every BLOCKING
  item of rounds 1–3 was confirmed fixed.
- **Tried.** Rounds 1–3 fixed what their reviews found; these two were first raised in round 4, the last TASK.md §5.5
  allows, so M4 gets no `port-M4-approved` tag.
- **What follows.** M5 builds on M4 unchanged (nothing M5 does depends on the two missing tests). Both fixes land at the
  start of M5's range, so M5's review and gates cover them: `WindowsSupport/ProviderHTTPWindowsTests` (a Winsock HTTP
  host on 127.0.0.1; the self-signed certificate rule needs a TLS host and stays untested, noted in the test) and
  `WindowsSupport/WindowsCredentialsTests` (a fixture generic credential under a unique `agenthud-test-…` target, written
  and deleted by the test; `gh:` targets never read). Until M5 is approved, SUPPORT_MATRIX's ✅ in the Quota column
  rests on the provider fixtures, not on a tested Windows transport.
- **Suggestion.** Close this entry when M5 is approved with those tests in its range.
