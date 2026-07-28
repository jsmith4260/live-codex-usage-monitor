# Changelog

## 3.3.0 - 2026-07-28

### Usage Saver

- Add a dedicated **Saver** workspace that keeps RTK shell-output savings, prompt-cache rate benefits, and optimization opportunities explicitly separate.
- Calculate cache-hit percentage and the avoided full-rate credit/API-equivalent difference from local cached-input counters and the dated bundled rate card.
- Add an advisory fresh-task break-even model based on recent replay size and observed fresh-session baselines.
- Add a short, removable local output-budget policy for targeted searches, narrow reads, quiet test output, RTK usage, and zero-outbound monitoring.
- Add an aggregate tool-surface audit that counts configured MCP sections versus locally observed tool categories without returning names or paths.

### High-value functional improvements

- Replace a single combined quota indicator in the Saver workspace with independent short- and long-window meters, reset labels, and even-pace status.
- Add context-efficiency and compaction-churn panels, including post-compaction reread-spike detection.
- Add versioned Codex JSONL schema-drift detection for unknown records, malformed records, token-counter changes, and quota-shape changes.
- Add allowlisted Codex configuration validation, Saver/Balanced/Quality previews, affirmative apply, safe duplicate/invalid-key repair, and local rollback.
- Preserve model selection, unknown TOML sections, automatic-compaction settings, credentials, server definitions, and all non-allowlisted configuration.

### Privacy and QA

- Keep prompts, responses, commands, arguments, paths, server names, and raw log content out of every efficiency result and persistent rollback file.
- Extend zero-outbound, aggregate-shape, parser, module, UI-construction, profile/repair/rollback, policy install/remove, quota, cache, schema, and compaction tests.
- Expand the Control Center to nine responsive tabs and include the efficiency module in release packaging.

### Project discoverability

- Redesign the README opening around a one-minute Windows quick start, clear search terms, current feature coverage, and explicit privacy boundaries.
- Publish deterministic dashboard and Usage Saver screenshots that contain fixture data only.
- Add CI, version, platform, PowerShell, and local-only badges plus a direct source download and feedback path.
- Make the release build reject a stale README version badge, missing changelog heading, or broken local README link.

## 3.2.0 - 2026-07-28

### Personal coverage

- Refocus the user-facing product on one individual and remove multi-user/department/seat administration from the normal workflow.
- Replace the Enterprise CSV action with a private **Import my data** chooser for personal usage-summary CSV and advanced activity JSONL exports.
- Reject usage summaries and activity exports containing more than one identity.
- Rename official/enterprise terminology to downloaded report, personal usage, activity export, and local comparison.

### Reliability and portability

- Add a Personal Settings tab with local backup/restore, integrity manifests, automatic pre-restore backups, and a strict aggregate/settings allowlist that excludes raw logs and imported source files.
- Add current-user start-at-sign-in registration with optional minimized-to-tray startup and no administrator requirement.
- Add sanitized health checks and diagnostic JSON export with no usernames, full paths, prompts, responses, or identifiers.
- Add combined RTK coverage and usage-guard reliability status, including a warning when enforced guard is armed but start-at-sign-in is off.

### QA

- Add personal/multi-user rejection fixtures, backup round-trip and integrity tests, startup-registration tests, diagnostic privacy tests, and visual QA for the personal settings and usage-summary surfaces.

## 3.1.0 - 2026-07-28

### RTK savings and health

- Add an optional local RTK integration with telemetry forcibly disabled for every monitor query.
- Add a dedicated RTK health tab with aggregate estimated tokens saved, reduction percentage, commands tracked, parser failures, and daily history.
- Distinguish healthy, idle, no-data, ineffective, unavailable, degraded, and possible-bypass states without claiming byte-derived estimates are billed-token or cash savings.
- Keep RTK command text, arguments, executable paths, and database paths out of monitor persistence and visible aggregate tables.

### Kill-switch clarity

- Make the default state explicit as `OFF - no process can be stopped`.
- Add outcome-based advisory, armed, grace, locked, and renewed status text.
- Add read-only exact-path/process-match verification, trigger/scope/grace summaries, and a more explicit enforced-mode confirmation.
- Preserve opt-in behavior: no threshold or process enforcement is enabled automatically.

### QA and packaging

- Add deterministic RTK parsing, savings, telemetry-block, possible-bypass, and guard-readiness tests.
- Include the RTK module in the zero-outbound release gate and packaged release.

## 3.0.0 - 2026-07-27

### Privacy and offline foundation

- Make zero outbound account/network activity and zero paid ChatGPT usage explicit runtime requirements.
- Add a release QA gate that rejects HTTP/account-polling code paths.
- Add provenance and freshness labels for local logs, bundled rates, local aggregate history, and imported official reports.
- Add an atomic, versioned, aggregate-only local history store with no prompt text, response text, identifiers, session names, or source paths.

### Insights and estimates

- Add a redesigned Control Center with daily trends, a text-backed chart, forecast, time-of-week heatmap, model mix, and source inventory.
- Add a dated bundled Codex credit-rate snapshot and exact known-model credit calculations.
- Show API-equivalent USD only where a current official standard API rate is available.
- Add local contract parameters for dollars per credit, included credits, fixed cycle cost, billing day, fallback model, and rate multiplier.
- Keep unknown models visibly unpriced instead of guessing.

### Official reconciliation and enterprise coverage

- Import and sanitize local official-usage CSV/JSON snapshots.
- Compare daily local estimated credits to official values with variance, coverage, and reporting-cadence freshness.
- Watch a local report folder without signing in or making an outbound request.
- Import multiple Workspace Analytics CSV reports into one identifier-free aggregate view.
- Retain the offline Compliance mapping boundary for supported ChatGPT desktop, web, Excel, PowerPoint, and other enterprise surfaces.

### Guard and usability

- Add an opt-in persistent usage guard with advisory/enforced modes, configurable metrics, grace time, exact executable allowlisting, and affirmative renewal until local midnight.
- Add a Fluent-inspired, DPI-aware WinForms redesign with calmer hierarchy, accessible contrast, keyboard mnemonics, descriptions, text-backed status colors, and redesigned mini mode.
- Add a system-tray menu for the dashboard, mini view, Control Center, and exit.
- Expand deterministic and visual QA across costs, reconciliation, persistence, guard mocks, zero-outbound enforcement, and all new UI surfaces.

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
