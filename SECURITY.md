# Security and privacy

Live Codex Usage Monitor is designed to read local Codex session logs and personal data exports without sending them anywhere.

## Defaults

- Prompt-derived task titles are disabled by default.
- Prompts, responses, tool arguments, tool output, credentials, and working-directory paths are not persisted or transmitted.
- The monitor does not require an OpenAI API key or network access.
- Runtime account polling and outbound HTTP clients are forbidden. `Test-ZeroOutbound.ps1` enforces this in release QA.
- Monitoring creates no ChatGPT turn, token, credit, API, agent, or other paid usage.
- Explicit CSV outputs contain aggregates only and exclude task names, session IDs, source paths, direct user identifiers, prompts, responses, and tool content.
- Repository rules exclude local JSONL session logs, generated telemetry, databases, and common secret-file formats.
- Persistent history contains aggregate dates/counters only. Guard and cost settings contain local numeric parameters and exact executable paths, never credentials.
- Optional RTK checks invoke only the configured local executable, force `RTK_TELEMETRY_DISABLED=1`, and read aggregate history/failure counters. The monitor does not persist command text, arguments, or RTK history.

## Usage guard boundary

The usage guard is disabled by default. Enforced mode requires explicit confirmation and exact executable paths, uses a visible grace period, and may terminate active work. Re-enabling a locked guard requires an affirmative in-app renewal. It does not modify firewall, AppLocker, registry, browser, Office, or workspace policy, and it cannot enforce after the monitor exits.

The Control Center distinguishes `OFF`, `ADVISORY`, `ARMED (ENFORCED)`, `GRACE`, `LOCKED`, and `RENEWED`. `OFF` means no warning threshold or process stop is active. A read-only path-verification action never stops a process.

## RTK boundary

RTK is optional and is not downloaded or updated by the monitor. Its reported "tokens saved" are approximate shell-output tokens derived from byte counts, not OpenAI-billed tokens, ChatGPT quota, or money. `Possible bypass` means recent local shell activity is newer than the RTK database; `Degraded` means RTK reported parse failures/fallbacks; `Working - no savings` means RTK tracked commands but did not reduce their output.

## Cost and downloaded-data boundary

The bundled rate card is a dated static snapshot. Unknown models are unpriced. API-equivalent USD is not a bill, and cash estimates require user-supplied contract parameters. Reconciliation reads only a local CSV/JSON selected or placed by the user; it never signs in or reads browser cookies.

## Reporting a vulnerability

Please report security or privacy concerns privately to the repository owner rather than opening a public issue containing sensitive logs or screenshots.

Include the affected version, reproduction steps, and a minimal sanitized example. Never attach real Codex session logs, prompts, credentials, customer data, or proprietary files.

## Personal data sources

The product is a single-user tool. Personal usage summaries and activity exports must be downloaded outside the app and filtered to one individual; multi-user imports are rejected. The offline normalizer returns only date/surface/type/model counts and discards prompt/response content and raw identifiers. The monitor does not contain a central collector, administrator dashboard, or credentialed account/activity API client.

## Personal backup and diagnostics

Personal backups use an allowlist containing aggregate history, guard settings, cost settings, and personal settings. They exclude raw Codex logs and imported source reports. Every backed-up entry has a SHA-256 integrity value verified before restore, and interactive restore creates a pre-restore backup.

Sanitized diagnostics contain check names, status words, and content-free descriptions only. They exclude usernames, full paths, source filenames, prompts, responses, IDs, and command text.
