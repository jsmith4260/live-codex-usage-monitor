# Changelog

## 2.0.0 - 2026-07-27

### Local monitor

- Discover both active `sessions` and `archived_sessions` Codex logs.
- Add Today, Last 7 days, Last 30 days, All available, and Custom ranges.
- Add command-line `-FromDate` and `-ToDate` support.
- Reuse an in-memory parsed catalog across range changes so presets do not reparse already loaded files.
- Show reset countdowns and even-pace context when current quota metadata permits.
- Add scanned-log counts and a status-colored headroom meter.
- Export privacy-safe daily CSV aggregates on explicit user request.
- Add keyboard shortcuts, accessible control names, tooltips, and improved mini-mode size restoration.

### Enterprise

- Import the official Workspace Analytics user CSV into a separate aggregate-only view.
- Aggregate seat types, departments, tools, and models without returning direct user identifiers.
- Add a mapping-driven offline Compliance Logs JSONL normalizer.
- Neutralize formula-active dimension labels before any enterprise aggregate is exported to CSV.
- Keep workspace credentials and live Compliance API calls outside the endpoint application.

### Quality and delivery

- Expand deterministic QA to cover archived logs, presets, command-line ranges, reset countdowns, enterprise imports, both export paths, and privacy invariants.
- Add visual screenshot smoke support for both dashboards.
- Add a reproducible release ZIP and SHA-256 manifest build.
- Update Windows CI to parse all PowerShell scripts/modules, run QA, build the release, and upload the artifact.

## 1.0.0

- Initial local Windows Codex token dashboard with incremental JSONL reading, date selectors, task/integration breakdowns, mini mode, quota status, alerts, privacy-safe labels, and Windows CI.
