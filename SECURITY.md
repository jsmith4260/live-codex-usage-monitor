# Security and privacy

Live Codex Usage Monitor is designed to read local Codex session logs and approved enterprise exports without sending them anywhere.

## Defaults

- Prompt-derived task titles are disabled by default.
- Prompts, responses, tool arguments, tool output, credentials, and working-directory paths are not persisted or transmitted.
- The monitor does not require an OpenAI API key or network access.
- Explicit CSV outputs contain aggregates only and exclude task names, session IDs, source paths, direct user identifiers, prompts, responses, and tool content.
- Repository rules exclude local JSONL session logs, generated telemetry, databases, and common secret-file formats.

## Reporting a vulnerability

Please report security or privacy concerns privately to the repository owner rather than opening a public issue containing sensitive logs or screenshots.

Include the affected version, reproduction steps, and a minimal sanitized example. Never attach real Codex session logs, prompts, credentials, customer data, or proprietary files.

## Enterprise data sources

Live Enterprise/Edu integrations should use a central least-privilege collector. Compliance API credentials must not be distributed to individual workstations. The included offline normalizer uses organization-supplied dot-path mappings and returns only date/surface/type/model counts and unique-user counts. Ingested prompt and response content should be discarded unless an organization has explicitly approved a documented compliance use case and retention policy.
