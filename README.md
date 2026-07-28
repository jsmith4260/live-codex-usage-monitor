# Live Codex Usage Monitor

An offline Windows dashboard for understanding local Codex usage telemetry, estimates, task activity, and optional RTK command-output savings. It reads data already stored on the workstation, then presents fresh token burn, replayed context, active tasks, quota windows, local tool activity, RTK health, trends, dated credit estimates, local official-report reconciliation, and an opt-in usage guard. It also opens one or more approved ChatGPT Enterprise/Edu Workspace Analytics CSV exports in a separate aggregate-only view.

## Purpose

Use this monitor to understand the shape of local Codex work without creating more ChatGPT work. It helps distinguish fresh token use from replayed context, identify unusually large turns, forecast usage, compare a downloaded official report with local estimates, and see which local tasks are active. Estimates are always labeled and are not an OpenAI invoice.

## Requirements

- Windows with PowerShell 5.1 or newer.
- Codex desktop or CLI that writes session logs under `~\.codex\sessions` or `~\.codex\archived_sessions`.
- No API key, account token, network connection, or additional package is required.
- RTK is optional. When installed, its local aggregate history powers the RTK health tab; the monitor never downloads RTK at runtime.

## Privacy and safety

- The monitor does not invoke Codex, call ChatGPT, poll an account endpoint, or contact a network service.
- Monitoring itself creates no ChatGPT messages, turns, tokens, credits, API requests, overages, agent activity, or other paid usage.
- Its automatic live input is existing local Codex JSONL. Official, Workspace Analytics, and Compliance data enter only through explicit local-file workflows.
- Optional RTK diagnostics read only RTK's local aggregate savings/history output. The monitor forces `RTK_TELEMETRY_DISABLED=1` for every RTK child process.
- Prompt-derived task names are disabled by default. Tasks use timestamp/session labels unless the optional `-ShowPromptTaskTitles` switch is supplied.
- Prompts, responses, tool arguments, tool output, credentials, client data, and working-directory paths are not persisted or transmitted.
- Local CSV output contains daily counts and token totals only. It excludes task names, session IDs, source paths, prompts, responses, and tool data.
- The optional persistent history under `%LOCALAPPDATA%\LiveCodexUsageMonitor` contains dates and aggregate counters only. It never contains prompts, responses, session names, account identifiers, or source paths. Use `-DisablePersistence` to turn it off.
- `Test-ZeroOutbound.ps1` is a release gate that rejects outbound-request APIs in production PowerShell sources.

## Start it

- Full dashboard by double-click: `Start-Live-Codex-Usage.cmd`
- Mini always-visible view by double-click: `Start-Live-Codex-Usage-Mini.cmd`
- Full dashboard from PowerShell:

```powershell
& .\Start-Live-Codex-Usage.ps1
```

- Mini view from PowerShell:

```powershell
& .\Start-Live-Codex-Usage-Mini.ps1
```

Do not paste the contents of a `.cmd` file into PowerShell. `.cmd` files are batch files for Command Prompt/double-click; `.ps1` files are PowerShell scripts.

- Manual PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -StartMini
```

## Useful options

```powershell
# Watch all active tasks instead of only the latest one
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -InitialView "All sessions"

# Set the initial startup window to the last 48 hours
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -HistoryHours 48

# Start on an exact inclusive date range
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -FromDate 2026-07-01 -ToDate 2026-07-31

# Exclude archived sessions when only active history is wanted
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -IncludeArchivedSessions:$false

# Opt in to in-memory task titles derived from local requests
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -ShowPromptTaskTitles

# Raise or lower spike thresholds
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -WarnMinuteFreshTokens 50000 -WarnContextTokens 150000

# Disable RTK health checks for this launch, or point to an approved RTK binary
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -DisableRtkIntegration
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -RtkExecutablePath C:\ApprovedTools\rtk.exe
```

## What it tracks

- Fresh token burn: new input + output. Reasoning tokens are displayed separately but are already included in output.
- Replayed context separately from fresh work, so cached context does not look like a new charge.
- Task/session breakdown with model, effort/options when present in logs, averages, cache ratio, and health.
- View buttons for All tasks, Latest, and Pinned.
- **Today**, **Last 7 days**, **Last 30 days**, **All available**, and **Custom** history ranges.
- **From** and **To** calendar selectors that load complete local history for any inclusive date range.
- Active and archived Codex sessions.
- Privacy-safe timestamp/session task names by default. Prompt-derived display names are an explicit opt-in and remain in memory only.
- Integration/tool activity counts by local shell, file edits, web, MCP/app/plugin names, waits, and plan updates.
- Optional RTK aggregate shell-output savings, daily reduction estimates, freshness, parser failures, and possible-prefix-bypass warnings.
- OK/WARN/CRITICAL status, a matching color meter, quota reset countdowns, and an even-pace comparison when the log supplies a window duration.
- Privacy-safe daily CSV export through **Export CSV**.
- A system-tray menu with dashboard, mini-mode, Control Center, and exit actions.

## Control Center

Open **Control center** or press `Ctrl+I`.

- **Trends**: daily fresh-token history, a trailing observed-day forecast, and a text table matching the chart.
- **Heatmap**: local day/hour activity with both text and an accessible color-intensity cue.
- **RTK health**: local-only command-output reduction estimates, daily history, freshness, parser/fallback failures, and possible bypass status.
- **Cost**: official credit estimates for known models, API-equivalent USD only where a current official API rate is published, and optional contract parameters for a configured cash estimate.
- **Reconcile**: local daily credit estimates versus a downloaded official CSV/JSON, with variance, coverage, and freshness labels.
- **Usage guard**: disabled by default. Advisory mode warns; explicitly approved Enforced mode stops only exact user-approved Codex executable paths after a grace period.
- **Sources**: provenance, model mix, state locations, and the privacy/zero-cost contract.

The bundled rate card is dated. Unknown model names remain unpriced; the app never guesses a fallback unless you explicitly configure one. Fast or special service tiers can use a user-supplied multiplier. Actual dollars are shown only after you provide your own dollars-per-credit, included-credit, fixed-cost, and billing-cycle parameters.

Official reporting is not real-time. Workspace Analytics normally refreshes in 1-24 hours, typically 6-12 hours, with a service target of up to 48 hours. The app labels report age and never fetches the report itself. Put approved snapshots in `%LOCALAPPDATA%\LiveCodexUsageMonitor\official-reports` or select a local file.

See [offline cost, reconciliation, and guard details](docs/OFFLINE-COST-RECONCILIATION-GUARD.md).
See [RTK savings and health](docs/RTK-SAVINGS-AND-HEALTH.md) for exact measurement and failure-state semantics.

## Reading the dashboard

- **Fresh** is uncached/new input plus output for a completed turn. Reasoning is a subset of output and is not counted twice.
- **Context** is the total context presented to the model. Much of it can be cached/replayed task history, so it is not equivalent to new usage.
- **Last 60 seconds** is the live window used for the header status and meter. Older task spikes do not keep the header in a Critical state.
- **Task breakdown** groups activity by local Codex session. Use **Latest** to follow the newest task or double-click a task to pin it.
- **Integrations/add-ins/plugins** shows call counts and names only. It does not show tool inputs or outputs.
- **Sanitized activity** shows event types such as token updates, messages, and tool activity, not their content.
- **logs loaded/available** confirms how many active and archived JSONL files are contributing to the current window.

## Keyboard shortcuts

- `Ctrl+L`: load the selected date range.
- `Ctrl+E`: export the visible privacy-safe daily summary.
- `Ctrl+M`: toggle mini mode.
- `Ctrl+I`: open the Control Center.
- `F5`: refresh immediately.

## Status behavior

The header is **OK**, **WARN**, or **CRITICAL** based on the latest quota metadata when present; otherwise it evaluates fresh token use in the last minute plus active task health. A previous task's spike cannot leave the monitor stuck at Critical after the task is no longer active.

## Enterprise-wide ChatGPT coverage

ChatGPT desktop, web, Excel, and PowerPoint do not write the same Codex JSONL token events. Reliable enterprise reporting should come from OpenAI workspace data rather than browser interception, process scraping, or keylogging.

Click **Enterprise CSV** and open one or more Workspace Analytics user CSVs exported by an authorized ChatGPT Enterprise/Edu administrator. The separate view reports aggregate active users, message totals, seat types, departments, tools, and models. It never displays or returns names, email addresses, public IDs, or account IDs.

For approved Compliance exports, open **Control center > Sources > Open Compliance export** and select the local JSONL plus your organization's mapping file. The aggregate-only surface reports date, product surface (for example web or Excel when present in the source), event type, model, and counts; prompt/response content and raw user identifiers are discarded.

See the [Enterprise data-source roadmap](docs/ENTERPRISE-DATA-SOURCES.md) for the supported architecture and [Compliance export normalizer](docs/COMPLIANCE-NORMALIZER.md) for the mapping-driven, content-free JSONL adapter. [Design and research decisions](docs/DESIGN-AND-RESEARCH.md) explains which ideas from comparable monitors were adopted or rejected.

## Offline Compliance export normalization

After an Enterprise/Edu administrator validates the current authenticated event schema, adapt `config\compliance-mapping.example.json` and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Convert-Enterprise-ComplianceExport.ps1 `
  -InputPath C:\ApprovedInput\compliance-export.jsonl `
  -MappingPath .\config\compliance-mapping.example.json `
  -OutputPath C:\ApprovedOutput\compliance-summary.csv
```

The result contains date, surface, event type, model, event count, and unique-user count only. The tool does not call the Compliance API or retain a raw identifier.

## What it does not do

- It does not call OpenAI.
- It does not send local logs anywhere.
- It does not persist raw telemetry. The enabled-by-default local history store contains aggregate daily counters only and can be disabled with `-DisablePersistence`.
- It does not persist or send prompts, responses, tool arguments, tool output, credentials, client data, or working-directory paths. Prompt-derived task names are disabled by default; if explicitly enabled, they remain only in memory while the dashboard is open.
- It does not claim estimates are an OpenAI invoice or account balance.
- It does not claim RTK's byte-derived shell-output estimate is a billed-token count, quota reduction, or cash saving.
- It does not silently price unknown models or assign an actual cash value to a credit.
- It does not implement a live Compliance API collector without the organization's current authenticated schema, approved service identity, and retention controls.
- It does not inspect browser cookies/history, Office documents, prompts, keystrokes, TLS traffic, or private account endpoints.
- The local guard does not block ChatGPT web, Office add-ins, another device, or launches after the monitor exits. Enterprise-mandatory blocking belongs in approved workspace and endpoint policies.

## QA

Double-click `Test-Live-Codex-Usage.cmd`, or run:

```powershell
& .\Test-Live-Codex-Usage.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -Once
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -UiSmokeTest -NoNotifications -NoSound
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -MiniSmokeTest -NoNotifications -NoSound
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -IntegrationSmokeTest
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -TaskSmokeTest
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -DateRangeSmokeTest
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -StatusSmokeTest
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -AlertSmokeTest
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -InsightsUiSmokeTest -DisablePersistence
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-ZeroOutbound.ps1
```

The test wrapper uses deterministic local fixtures, checks child exit codes, verifies fresh-token semantics, exercises date ranges and archived logs, validates both quota windows, constructs all UI surfaces, tests RTK health with a fake local runner, tests pricing/reconciliation/persistence/guard logic with fake processes, and proves that aggregate outputs do not expose fixture prompt text or direct identifiers.

## Build a release

```powershell
& .\Build-Release.ps1
```

The build parses every PowerShell file, runs the full QA suite, and creates a versioned ZIP plus SHA-256 manifest under `artifacts`. GitHub Actions performs the same validation and publishes the package as a workflow artifact.
