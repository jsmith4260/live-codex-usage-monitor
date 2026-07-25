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
- The dashboard displays a short task name derived from the first local user request. That name remains only in memory while the window is open; it is never saved or sent.
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

# Rebuild the dashboard from the last 48 hours of local logs
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -HistoryHours 48

# Raise or lower spike thresholds
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -WarnMinuteFreshTokens 50000 -WarnContextTokens 150000
```

## What it tracks

- Fresh token burn: new input + output + reasoning.
- Replayed context separately from fresh work, so cached context does not look like a new charge.
- Task/session breakdown with model, effort/options when present in logs, averages, cache ratio, and health.
- View buttons for All tasks, Latest, and Pinned. The old dropdown was removed because it rendered as a black box on some Windows themes.
- Display-only task names from the first local user request, kept only in memory while the dashboard is open; they are never written to disk or sent anywhere.
- Integration/tool activity counts by local shell, file edits, web, MCP/app/plugin names, waits, and plan updates.
- OK/WARN/CRITICAL status and a headroom-style meter.

## Reading the dashboard

- **Fresh** is new input plus output and reasoning for a completed turn. It is the best signal for new work introduced by that turn.
- **Context** is the total context presented to the model. Much of it can be cached/replayed task history, so it is not equivalent to new usage.
- **Last 60 seconds** is the live window used for the header status and meter. Older task spikes do not keep the header in a Critical state.
- **Task breakdown** groups activity by local Codex session. Use **Latest** to follow the newest task or double-click a task to pin it.
- **Integrations/add-ins/plugins** shows call counts and names only. It does not show tool inputs or outputs.
- **Sanitized activity** shows event types such as token updates, messages, and tool activity, not their content.

## Status behavior

The header is **OK**, **WARN**, or **CRITICAL** based on the latest quota metadata when present; otherwise it evaluates fresh token use in the last minute plus active task health. A previous task’s spike cannot leave the monitor stuck at Critical after the task is no longer active.

## What it does not do

- It does not call OpenAI.
- It does not send local logs anywhere.
- It does not write files or persist telemetry.
- It does not persist or send prompts, responses, tool arguments, tool output, credentials, client data, or working-directory paths. Display-only task names are the sole exception: they are extracted from the first local request and retained only in memory while the dashboard is open.
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
```
