# Live Codex Usage Monitor

An offline Windows dashboard for understanding local Codex usage telemetry and task activity. It reads the Codex session logs already stored on the workstation, then presents fresh token burn, replayed context, active tasks, quota windows, and local tool activity in one live view. Version 2 also opens approved ChatGPT Enterprise/Edu Workspace Analytics CSV exports in a separate aggregate-only view.

## Purpose

Use this monitor to understand the shape of local Codex work without changing that work. It helps distinguish fresh token use from replayed context, identify unusually large turns, and see which local tasks are active. It is operational telemetry, not billing data or an OpenAI invoice.

## Requirements

- Windows with PowerShell 5.1 or newer.
- Codex desktop or CLI that writes session logs under `~\.codex\sessions` or `~\.codex\archived_sessions`.
- No API key, account token, network connection, or additional package installation.

## Privacy and safety

- The monitor does not invoke Codex, call ChatGPT, or contact a network service.
- It writes only when a user explicitly chooses a sanitized local CSV export or runs the offline Compliance export normalizer.
- It reads existing local Codex JSONL session logs only.
- Prompt-derived task names are disabled by default. Tasks use timestamp/session labels unless the optional `-ShowPromptTaskTitles` switch is supplied.
- Prompts, responses, tool arguments, tool output, credentials, client data, and working-directory paths are not persisted or transmitted.
- Local CSV output contains daily counts and token totals only. It excludes task names, session IDs, source paths, prompts, responses, and tool data.

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
- OK/WARN/CRITICAL status, a matching color meter, quota reset countdowns, and an even-pace comparison when the log supplies a window duration.
- Privacy-safe daily CSV export through **Export CSV**.

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
- `F5`: refresh immediately.

## Status behavior

The header is **OK**, **WARN**, or **CRITICAL** based on the latest quota metadata when present; otherwise it evaluates fresh token use in the last minute plus active task health. A previous task's spike cannot leave the monitor stuck at Critical after the task is no longer active.

## Enterprise-wide ChatGPT coverage

ChatGPT desktop, web, Excel, and PowerPoint do not write the same Codex JSONL token events. Reliable enterprise reporting should come from OpenAI workspace data rather than browser interception, process scraping, or keylogging.

Click **Enterprise** and open a Workspace Analytics user CSV exported by an authorized ChatGPT Enterprise/Edu administrator. The separate view reports aggregate active users, message totals, seat types, departments, tools, and models. It never displays or returns names, email addresses, public IDs, or account IDs.

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
- It does not persist telemetry unless a user explicitly requests one of the aggregate CSV outputs.
- It does not persist or send prompts, responses, tool arguments, tool output, credentials, client data, or working-directory paths. Prompt-derived task names are disabled by default; if explicitly enabled, they remain only in memory while the dashboard is open.
- It is local telemetry, not an OpenAI invoice.
- It does not estimate cost from a bundled pricing table.
- It does not implement a live Compliance API collector without the organization’s current authenticated schema, approved service identity, and retention controls.

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
```

The test wrapper uses deterministic local fixtures, checks child exit codes, verifies fresh-token semantics, exercises date ranges and archived logs, validates both quota windows, constructs both UIs, and proves that local, Workspace Analytics, and Compliance aggregate outputs do not expose fixture prompt text or direct identifiers.

## Build a release

```powershell
& .\Build-Release.ps1
```

The build parses every PowerShell file, runs the full QA suite, and creates a versioned ZIP plus SHA-256 manifest under `artifacts`. GitHub Actions performs the same validation and publishes the package as a workflow artifact.
