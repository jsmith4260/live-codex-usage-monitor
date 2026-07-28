# Security and privacy

Live Codex Usage Monitor is designed to read local Codex session logs and approved enterprise exports without sending them anywhere.

## Defaults

- Prompt-derived task titles are disabled by default.
- Prompts, responses, tool arguments, tool output, credentials, and working-directory paths are not persisted or transmitted.
- The monitor does not require an OpenAI API key or network access.
- Runtime account polling and outbound HTTP clients are forbidden. `Test-ZeroOutbound.ps1` enforces this in release QA.
- Monitoring creates no ChatGPT turn, token, credit, API, agent, or other paid usage.
- Explicit CSV outputs contain aggregates only and exclude task names, session IDs, source paths, direct user identifiers, prompts, responses, and tool content.
- Repository rules exclude local JSONL session logs, generated telemetry, databases, and common secret-file formats.
- Persistent history contains aggregate dates/counters only. Guard and cost settings contain local numeric parameters and exact executable paths, never credentials.

## Usage guard boundary

The usage guard is disabled by default. Enforced mode requires explicit confirmation and exact executable paths, uses a visible grace period, and may terminate active work. Re-enabling a locked guard requires an affirmative in-app renewal. It does not modify firewall, AppLocker, registry, browser, Office, or workspace policy, and it cannot enforce after the monitor exits.

## Cost and official data boundary

The bundled rate card is a dated static snapshot. Unknown models are unpriced. API-equivalent USD is not a bill, and cash estimates require user-supplied contract parameters. Official reconciliation reads only a local CSV/JSON selected or placed by the user; it never signs in or reads browser cookies.

## Reporting a vulnerability

Please report security or privacy concerns privately to the repository owner rather than opening a public issue containing sensitive logs or screenshots.

Include the affected version, reproduction steps, and a minimal sanitized example. Never attach real Codex session logs, prompts, credentials, customer data, or proprietary files.

## Enterprise data sources

Live Enterprise/Edu integrations should use a central least-privilege collector. Compliance API credentials must not be distributed to individual workstations. The included offline normalizer uses organization-supplied dot-path mappings and returns only date/surface/type/model counts and unique-user counts. Ingested prompt and response content should be discarded unless an organization has explicitly approved a documented compliance use case and retention policy.
