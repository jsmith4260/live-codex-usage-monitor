# Personal settings and recovery

The Settings tab is designed for one Windows user and keeps every operation local.

## Backup and restore

Personal backups may contain:

- aggregate daily history;
- usage-guard settings;
- cost-profile settings;
- personal monitor settings.

They never contain raw Codex JSONL, prompts, responses, command content, imported usage summaries, or activity exports. The ZIP includes a privacy-class manifest and a SHA-256 value for every entry. Restore rejects nested paths, unsupported files, unsupported schemas, and hash mismatches. The interactive restore workflow creates a local pre-restore backup first.

## Start with Windows

Start-at-sign-in creates a recognizable command file in the current Windows account's Startup folder. It requires no administrator permission and can start the monitor minimized to its tray icon. Disabling the option removes only a startup file carrying the monitor's identifying marker.

This improves guard continuity but is not a Windows service. Enforced guard behavior remains available only while the monitor process is running.

## Sanitized diagnostics

Health checks cover:

- local Codex log availability;
- aggregate persistence;
- local state-folder availability;
- RTK health, savings counters, failures, and telemetry block;
- usage-guard readiness;
- start-at-sign-in status;
- the zero-cost/privacy promise;
- application version.

Exported diagnostics omit usernames, full paths, source filenames, prompts, responses, identifiers, and command text.

## Personal imports

Usage-summary CSV and advanced activity JSONL imports must contain at most one distinct identity. Files containing multiple identities are rejected before a personal summary is displayed.
