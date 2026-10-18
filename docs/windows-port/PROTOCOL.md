# Engine ↔ shell protocol, version 1.3

How `AgentHUD.exe` (the WPF shell, M7) and `agenthud-engine.exe` (Swift, Support + Core) talk on Windows (ADR-001,
D-022, D-041). The engine computes; the shell shows what it is sent and sends back what the user did. No rule of Core
— alert levels, quota maths, session phases, formatting, settings validation — exists a second time in C#.

Machine-readable contract: `windows/protocol/schema/v1.schema.json` (JSON Schema, draft 2020-12 subset). Shared
fixtures: `windows/protocol/fixtures/`, read by the Swift tests (`ShellProtocolTests`) and the C# tests
(`windows/AgentHUD.Protocol.Tests`), and checked against the schema by `scripts/windows/check-protocol.py`.

## Transport

- The shell starts `agenthud-engine.exe --serve` as its child, with `CREATE_NO_WINDOW`, and gives it two anonymous
  pipes as standard input and output (standard error goes to the shell's log). Nothing else can open them.
- Each message is one line: a JSON object in UTF-8, no byte-order mark, ended by `\n` alone. A line holds at most
  16 MiB; a longer one is a protocol error.
- The engine writes protocol lines only through the standard output handle it inherited. At start it duplicates that
  handle for the protocol and points the C runtime's and Foundation's standard output at standard error, so a stray
  `print` in shared code cannot inject a line (D-022).
- The engine ends when its input ends (the shell quit or crashed) or when it is sent `quit`; before ending it lets
  every waiting approval go back to its client (`PermissionRequests.stop`).

## Envelope and versions

Every message has `"v": 1` (the protocol's major version) and `"type"`. A reader **rejects** a line that is not a
JSON object, has another `v`, or an unknown `type`: the engine answers it with `error` and goes on; the shell logs it
and ignores it. Within major version 1, minor versions only **add**: new optional fields, new message types a side
announces in `hello`. A reader ignores fields it does not know. Times are integers of milliseconds since 1970 UTC
(RecordCoding's millisecond dates); counts are integers; percentages are numbers in 0…100.

## The exchange

1. The shell sends `hello`. The engine answers `hello`, then either `lock-held` (another copy runs: it exits with
   status 3) or its first `state`.
2. The engine sends `state` whenever anything shown changed (coalesced to at most one per 100 ms), and `event` for
   each thing the HUD presents once (a quota alert, reset credits, a finished turn).
3. The shell sends `refresh`, `answer`, `update-settings` and `quit` as the user acts. The engine never waits for the
   shell: its lines are written by a thread of their own, so a slow, hung or gone reader holds that thread only, never
   the engine's work (taking hooks' requests, letting unanswered ones go after the hold time). A `hello` not yet
   written is replaced by a newer one where it stands, so a `hello` still comes before any `state`; a `state` not yet
   written gives way to a newer one at the end of the queue, after the lines before it. Other lines wait in order, at
   most 256 in all — when a stalled shell lets more pile up, an `error` is dropped first, then the oldest other line
   (an `event`), never the `hello` or the `state`. On exit the engine waits at most 2 s for its
   last lines (`lock-held` before status 3).
4. The engine reads each line as it ends with `\n`; a line over the limit is dropped up to its end and answered with
   `error`. The fixtures are LF-only (`.gitattributes`), and both test sides refuse a CR in them.

## Engine → shell

### `hello`

```json
{"v":1,"type":"hello","minor":3,"engine":{"version":"0"},"demo":false,"language":"en","strings":{"…":"…"}}
```

`language` is the language Core resolved (`zh` or `en`). `strings` holds the words of the shell's own chrome
(`ShellStrings`, Core), in that language; the shell has none of its own. A language change sends `hello` again.

### `lock-held`

`{"v":1,"type":"lock-held","holder":"C:\\…\\agenthud-engine.exe"}` — the copy that holds the instance lock
(`InstanceLock`); `holder` is null when it wrote none. The engine exits with status 3 after it.

### `state`

The whole of what the HUD shows, every time (a reader keeps the last one only):

| Field | Meaning |
| --- | --- |
| `generatedAt` | when the report it was built from was made; null before the first |
| `paused`, `error` | the store paused (`UsageStore.isPaused`), the last refresh's error text or null |
| `settings` | Core's own encoding of `Settings` (`JSONEncoder`, sorted keys); the shell edits by sending patches |
| `panel` | the panel's projection of `ReportView` (below) |
| `approvals` | the requests waiting for the user (`PermissionRequests.pending`), oldest first |

`panel`: `now`; `maxUsedPct`; `glow` (`[{vendor, level}]`, `level` one of `ok`, `warning`, `critical`); `marks` (1.1:
the resting HUD's logo queue, `ReportView.queueMarks` in its order: `[{key, vendor, isWorking, waiting}]`, `key` the
mark vendors that share artwork share, `VendorMark.key`, and `waiting` whether a request of its sessions waits);
`agents` (one per `ReportView.rows` entry: `id`, `vendor`, `model`, `shortModel`, `level`, `usedPct`, `remainingPct`,
`weeklyRemainingPct`, `resetAt`, `resetText`, `missingQuotaLabel`, `paletteIndex`, `isCurrentAccount`,
`forecastHint`, and from 1.1 `modelText` and `shortModelText`, the row's label and its short form as the panel writes
them, `L10n.modelLabel` and `shortModelLabel` — "Current session", "Weekly limit · Fable", "5h" — and `mark`);
`sessions` (one per `ReportView.sessions` entry: `id`, `agentId`, `task`, `project`, `phase` (`running`,
`waitingForApproval`, `idle`, `unverified`), `phaseText`, `startedAt`, `lastEventAt`, `message`, `liveStatus`,
`tokensIn`, `tokensOut`, `cacheReadTokens`, `tokensText`, and from 1.1 `vendor`, the agent it ran in,
`SessionSource.agentVendor`, and its `mark`, both null when Core knows none). Every `…Text` is Core's formatting in the
resolved language, by the rules the macOS panel uses: `resetText` is `AgentRow.resetLabel` ("Pending update" once a
reset's time has passed, "—" for an account that is not current), `phaseText` is `UsageStore.sessionStatusLabel`
("Needs approval", "Status out of date", "Live status off", or the running or idle time), `project` is
`SessionProject`'s title (a repository's worktrees share it), `tokensText` is `TokenFormat.inOut` (the in/out pair,
not the panel row's shorter total, which comes with the row's title in M7, D-043). A reset more than a day off is
labelled by weekday and time in the engine's time zone, Windows' own (`WindowsTimeZone`, D-050).

Version 1.0 does not carry the balances (`billing`), the grouping of rows into accounts, the account and source
notices, or the token columns of the last 24 hours. The shell shows none of them until a minor version adds them, and
never works them out from the fields above (grouping rows by `vendor`, summing sessions' tokens): those are Core's rules.

An approval: `id`, `source`, `vendor`, `sessionID`, `toolName`, `summary`, `detail`, `project`, `path`, `removed`,
`added`, `at`, `isQuestion`, `questions` (`[{key, question, header, multiSelect, options: [{label, description}]}]`),
`isPlan`, `plan`, `answersPlan`, `alwaysAllowRule` (the rule an "Always allow" would add, or null when the client
offers none — then the shell shows no such button), and from 1.1 `mark`.

### Version 1.3

1.3 adds the statistics window's figures. The shell sends `{"v":1,"type":"statistics"}` when the window opens and again
with each new report; the engine answers `statistics`: `generatedAt`, `title`, `dimensions` (the token kinds counted)
and `periods`, Today, the last seven days and the last thirty, each with `period`, `label`, `total`, `cost`,
`cacheHits`, `models` (every model that spent tokens, the most first: `id`, `name`, `displayName`, `vendor`, `mark`,
`tokens`, `share` of the period's whole, Core's `paletteIndex`), `listed` (how many of them the card names) and `rest`
(`{text, tokens}` for the others, or null). It is the macOS Desktop's `UsagePeriodsCard` made by `ShellStatistics`, each
word source-checked as the events' are. A 1.2 engine answers the request with `error` (an unknown type).

### Version 1.2

1.2 adds to every `event` its `copy`, the card's words as the macOS Desktop's own copy makes them
(`ShellEventCopy`: `QuotaAlertCopy`, `ResetCreditAlertCopy`, the reply card), so the shell never words an event: a
quota alert's `vendorName`, `agentName`, `displayName`, `compactTitle` (the short line beside the mark), `title`,
`badge`, `warning`, `usedPct`, `metrics` (`[{value, label}]`, three) and `otherLimits`; reset credits' `vendorName`,
`compactTitle`, `title`, `badge`, `warning`, `metrics`; a reply's `status`, `title` (its task), `vendorName` and
`warning`. A quota alert and a reply also carry their `mark`. A shell shows no event of a 1.1 engine, which sends no
words for it.

### Version 1.1

1.1 adds `panel.marks`, the agent rows' `modelText`, `shortModelText` and `mark`, the sessions' `vendor` and `mark`,
and the approvals' `mark` (M7: the shell's resting HUD and labels, which it may not work out itself). The schema
lists them as the engine of this version sends them; a shell reads a 1.0 engine's state without them, an empty queue
and each row labelled by its `model` as given (`AStateWithoutTheFieldsOf11IsRead`).

### `event`

`{"v":1,"type":"event","event":{"kind":"…", …}}` with `kind` one of `quotaAlert` (`id`, `alert` — `exhaustion` or
`reset` —, `agentId`, `vendor`, `model`, `preview`, `timeToExhaust` in seconds or null, `timeToExhaustText`,
`alsoExhausted` — the ids of other agents out of quota), `resetCredits` (`id`, `added`, `preview`, `provider`,
`accountLabel` — whose account gained them), `completion`
(`id`, `sessionID`, `vendor`, `task`, `model`, `startedAt`, `completedAt`). The engine decides what is an event
(`IslandEventTracker`); the shell only shows it. The sentences the macOS Desktop composes around these facts reach the
shell through `ShellStrings` with M7 (D-043).

### `error`

`{"v":1,"type":"error","message":"…"}` — a line the engine could not take; nothing else changed.

## Shell → engine

| Message | Fields | Effect |
| --- | --- | --- |
| `hello` | `minor`, `shell: {version}` | starts the exchange |
| `refresh` | — | `UsageStore.refresh()` |
| `answer` | `id`, `decision` (`allow`, `deny`, `allowAlways`, `answer`, `approvePlan`, `keepPlanning`, `leave`); `answers` for `answer` (`{key: {selected: [label], custom: text or null}}`); `acceptEdits` for `approvePlan`; `note` for `keepPlanning` | `PermissionRequests.resolve` with Core's own `alwaysAllow` value for `allowAlways`; an unknown id is ignored, as on macOS |
| `update-settings` | `patch` (an object of `Settings` fields) | merged into Core's encoding of the current settings and decoded by Core; a patch naming a field `Settings` does not have, or one Core cannot decode, is answered with `error` and changes nothing. Core's decoder corrects some values instead of refusing them, as it does for the macOS app's own preferences (an unknown `appearance` becomes `system`, an `approvalWaitMinutes` outside its choices becomes 10): the next `state` shows what was kept |
| `quit` | — | lets every waiting approval go back to its client and exits 0 |

The HUD never answers for the user: only an `answer` the shell sends because the user chose resolves a request, and
a request nobody answers goes back to its client after the hold time, as on macOS.
