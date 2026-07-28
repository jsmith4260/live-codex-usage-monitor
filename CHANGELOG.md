# Changelog

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
