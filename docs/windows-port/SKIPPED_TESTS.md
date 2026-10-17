# Skipped and excluded tests

Every test that does not run on Windows, with the reason and its Windows counterpart (TASK.md §6 G3). A skip that is
not listed here counts as a failure.

## AgentHUDSupportTests

None: all Support tests run on Windows (M2). `portableDigestsEqualCryptoKit` compiles only where CryptoKit exists; it
is a macOS-only comparison by design, and the NIST and golden tests are its Windows counterpart.

## AgentHUDCoreTests

Core joins the Windows build in M3; this section is filled then (PORTING_PLAN.md §6 lists the planned exclusions).
