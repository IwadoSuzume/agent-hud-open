# Engine ↔ shell protocol, version 1.0

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
   shell: a slow reader only delays its own lines.

## Engine → shell

### `hello`

```json
{"v":1,"type":"hello","minor":0,"engine":{"version":"0"},"demo":false,"language":"en","strings":{"…":"…"}}
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

`panel`: `now`; `maxUsedPct`; `glow` (`[{vendor, level}]`, `level` one of `ok`, `warning`, `critical`); `agents`
(one per `ReportView.rows` entry: `id`, `vendor`, `model`, `shortModel`, `level`, `usedPct`, `remainingPct`,
`weeklyRemainingPct`, `resetAt`, `resetText`, `missingQuotaLabel`, `paletteIndex`, `isCurrentAccount`,
`forecastHint`); `sessions` (one per `ReportView.sessions` entry: `id`, `agentId`, `task`, `project`, `phase`
(`running`, `waitingForApproval`, `idle`, `unverified`), `phaseText`, `startedAt`, `lastEventAt`, `message`,
`liveStatus`, `tokensIn`, `tokensOut`, `cacheReadTokens`, `tokensText`). Every `…Text` is Core's formatting in the
resolved language.

An approval: `id`, `source`, `vendor`, `sessionID`, `toolName`, `summary`, `detail`, `project`, `path`, `removed`,
`added`, `at`, `isQuestion`, `questions` (`[{key, question, header, multiSelect, options: [{label, description}]}]`),
`isPlan`, `plan`, `answersPlan`, `alwaysAllowRule` (the rule an "Always allow" would add, or null when the client
offers none — then the shell shows no such button).

### `event`

`{"v":1,"type":"event","event":{"kind":"…", …}}` with `kind` one of `quotaAlert` (`id`, `alert` — `exhaustion` or
`reset` —, `agentId`, `vendor`, `model`, `preview`, `timeToExhaust` in seconds or null, `timeToExhaustText`,
`alsoExhausted` — the ids of other agents out of quota), `resetCredits` (`id`, `added`, `preview`), `completion`
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
| `update-settings` | `patch` (an object of `Settings` fields) | merged into Core's encoding of the current settings and decoded by Core; a patch Core cannot decode is answered with `error` and changes nothing |
| `quit` | — | lets every waiting approval go back to its client and exits 0 |

The HUD never answers for the user: only an `answer` the shell sends because the user chose resolves a request, and
a request nobody answers goes back to its client after the hold time, as on macOS.
