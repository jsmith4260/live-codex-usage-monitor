# Live Codex Usage Monitor

A read-only Windows dashboard for understanding local Codex usage telemetry and task activity. It reads the Codex session logs already stored on the workstation, then presents fresh token burn, replayed context, active tasks, and local tool activity in one live view.

## Purpose

Use this monitor to understand the shape of local Codex work without changing that work. It helps distinguish fresh token use from replayed context, identify unusually large turns, and see which local tasks are active. It is operational telemetry, not billing data or an OpenAI invoice.

## Requirements

- Windows with PowerShell 5.1 or newer.
- Codex desktop or CLI that writes session logs under `~\.codex\sessions`.
- No API key, account token, network connection, or additional package installation.

## Privacy and safety

- The monitor is read-only: it does not invoke Codex, call ChatGPT, contact a network service, or write history/export files.
- It reads existing local Codex JSONL session logs only.
- Prompt-derived task names are disabled by default. Tasks use timestamp/session labels unless the optional `-ShowPromptTaskTitles` switch is supplied.
- Prompts, responses, tool arguments, tool output, credentials, client data, and working-directory paths are not persisted or transmitted.

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
- **From** and **To** calendar selectors that can load complete local history for any selected date range.
- Privacy-safe timestamp/session task names by default. Prompt-derived display names are an explicit opt-in and remain in memory only.
- Integration/tool activity counts by local shell, file edits, web, MCP/app/plugin names, waits, and plan updates.
- OK/WARN/CRITICAL status and a headroom-style meter.

## Reading the dashboard

- **Fresh** is uncached/new input plus output for a completed turn. Reasoning is a subset of output and is not counted twice.
- **Context** is the total context presented to the model. Much of it can be cached/replayed task history, so it is not equivalent to new usage.
- **Last 60 seconds** is the live window used for the header status and meter. Older task spikes do not keep the header in a Critical state.
- **Task breakdown** groups activity by local Codex session. Use **Latest** to follow the newest task or double-click a task to pin it.
- **Integrations/add-ins/plugins** shows call counts and names only. It does not show tool inputs or outputs.
- **Sanitized activity** shows event types such as token updates, messages, and tool activity, not their content.

## Status behavior

The header is **OK**, **WARN**, or **CRITICAL** based on the latest quota metadata when present; otherwise it evaluates fresh token use in the last minute plus active task health. A previous task's spike cannot leave the monitor stuck at Critical after the task is no longer active.

## Enterprise-wide ChatGPT coverage

This release deliberately keeps the workstation monitor local and Codex-only. ChatGPT desktop, web, Excel, and PowerPoint do not write the same Codex JSONL token events, so reliable enterprise reporting should come from OpenAI workspace data rather than browser interception, process scraping, or keylogging.

See [Enterprise data-source roadmap](docs/ENTERPRISE-DATA-SOURCES.md) for the recommended architecture using Workspace Analytics exports and the Enterprise/Edu Compliance Platform. That approach can cover supported ChatGPT surfaces while keeping privileged workspace credentials off endpoints.

## What it does not do

- It does not call OpenAI.
- It does not send local logs anywhere.
- It does not write files or persist telemetry.
- It does not persist or send prompts, responses, tool arguments, tool output, credentials, client data, or working-directory paths. Prompt-derived task names are disabled by default; if explicitly enabled, they remain only in memory while the dashboard is open.
- It is local telemetry, not an OpenAI invoice.

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

The test wrapper uses deterministic local fixtures, checks child exit codes, verifies fresh-token semantics, exercises date-range reloads, validates both quota windows, and confirms that task labels do not expose prompt text by default.
