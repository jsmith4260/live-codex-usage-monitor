# Usage Saver and efficiency

The Saver workspace is a local decision-support and configuration surface. It does not invoke Codex, call ChatGPT, poll an account, use an API key, or create any token, turn, credit, agent, subscription, or other paid activity.

## Savings labels

The app deliberately keeps unlike measurements separate:

- **RTK estimated savings** are approximate shell-output tokens derived from RTK's local byte counters. They are not OpenAI-billed tokens or cash.
- **Cache benefit** is calculated from local cached-input counters and the difference between full-input and cached-input values in the dated bundled rate card.
- **Fresh-task advice** is an opportunity estimate based on recent replay size, observed fresh-session baselines, and an estimated break-even number of future turns.
- **Tool-surface review** is a count-based opportunity. The monitor never disables a tool or plugin automatically.

These values are never added into one synthetic "total saved" number.

## Independent quota windows

The Saver tab displays short and long quota windows independently when both are present in the latest local token event. Each window includes percentage used, percentage remaining, a reset countdown when supplied, and an even-pace comparison when the window duration is supplied.

Missing fields remain visibly unavailable. The monitor does not sign in or make an account request to fill them.

## Context and compaction health

The fresh-task advisor compares the recent average input replay with the median first-turn input observed across loaded local sessions. It recommends a fresh task only when replay is materially elevated and the estimated cold-start cost is likely to break even within a few future turns.

Compaction health pairs content-free compaction timestamps with the nearest local token events in the same in-memory session. It reports compaction frequency, approximate context reduction, and post-compaction fresh-input spikes. Session identifiers are used only in memory for pairing and are not returned or persisted.

## Schema-drift detection

The versioned schema tracker keeps aggregate counters only. It checks:

- known outer Codex rollout record types;
- expected cached, input, output, and total counters in token events;
- primary/secondary quota-window shape when rate-limit metadata is present;
- malformed or type-less completed JSONL records;
- local compaction markers.

It never stores or displays a raw line, prompt, response, tool argument, tool output, source path, session name, or identifier. A drift warning means the parser should be reviewed; it does not send the record anywhere.

## Efficiency profiles

The profiles change only these allowlisted top-level Codex settings:

- `model_reasoning_effort`
- `model_verbosity`

The profile choices are:

- **Saver**: low reasoning effort and low verbosity.
- **Balanced**: medium reasoning effort and low verbosity.
- **Quality**: high reasoning effort and medium verbosity.

The monitor leaves the selected model, automatic-compaction threshold, MCP/server definitions, features, credentials, provider configuration, and all unknown TOML sections untouched.

Every apply operation requires an affirmative in-app confirmation. Before the write, the monitor stores only the previous values/presence of the three allowlisted efficiency keys in `%LOCALAPPDATA%\LiveCodexUsageMonitor\codex-efficiency-rollback-v1.json`. It does not copy the full `config.toml`. Rollback restores only those allowlisted values. Restart Codex after an applied profile or rollback so future sessions consistently use the new settings.

## Configuration validation and safe repair

Validation is read-only. It recognizes only the model label and the three allowlisted efficiency settings, and returns no path or unknown configuration value.

Safe repair is enabled only when duplicate or invalid allowlisted values are detected. It requires confirmation, creates the allowlisted rollback first, normalizes valid values, removes invalid duplicates, and preserves every unknown top-level line and table.

## Local output-budget policy

The optional policy installs one marked block in the current user's `.codex\AGENTS.md`. The block asks future Codex work to use RTK for supported verbose commands, prefer targeted searches and narrow file reads, cap exploratory output, use quiet tests when appropriate, reuse unchanged context, and keep monitor data local.

The app modifies only its exact marked block. Existing personal instructions are preserved. Installation and removal both require an affirmative click. Unbalanced markers are never repaired automatically.

## Tool-surface audit

The audit counts configured MCP table sections and unique locally observed integration categories. It returns counts and a review suggestion only—never server names, tool names, configuration paths, commands, or arguments. Recommendations are advisory and no tool is disabled automatically.

