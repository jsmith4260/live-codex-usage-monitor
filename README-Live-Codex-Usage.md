# Live Codex Usage Monitor

This is a read-only, local-only Windows dashboard for Codex usage telemetry. It reads Codex JSONL session logs from `~\.codex\sessions` and shows token spikes within seconds. It never writes a history or export file, invokes Codex, calls ChatGPT, or contacts a network service.

## Start it

- Full dashboard by double-click: `Start-Live-Codex-Usage.cmd`
- Mini always-visible view by double-click: `Start-Live-Codex-Usage-Mini.cmd`
- Full dashboard from PowerShell:

```powershell
& "C:\Users\JRSmith\Documents\Codex\2026-07-24\what\outputs\Start-Live-Codex-Usage.ps1"
```

- Mini view from PowerShell:

```powershell
& "C:\Users\JRSmith\Documents\Codex\2026-07-24\what\outputs\Start-Live-Codex-Usage-Mini.ps1"
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

## What it does not do

- It does not call OpenAI.
- It does not send local logs anywhere.
- It does not write files or persist telemetry.
- It does not persist or send prompts, responses, tool arguments, tool output, credentials, client data, or working-directory paths. Display-only task names are the sole exception: they are extracted from the first local request and retained only in memory while the dashboard is open.
- It is local telemetry, not an OpenAI invoice.

## QA

Double-click `Test-Live-Codex-Usage.cmd`, or run:

```powershell
& "C:\Users\JRSmith\Documents\Codex\2026-07-24\what\outputs\Test-Live-Codex-Usage.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -Once
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -UiSmokeTest -NoNotifications -NoSound
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -MiniSmokeTest -NoNotifications -NoSound
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -IntegrationSmokeTest
powershell -NoProfile -ExecutionPolicy Bypass -File .\Live-Codex-Usage-GUI.ps1 -TaskSmokeTest
```
