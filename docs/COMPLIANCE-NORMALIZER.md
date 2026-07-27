# Compliance export normalizer

`Convert-Enterprise-ComplianceExport.ps1` is an offline, schema-mapped boundary for Enterprise/Edu Compliance Logs exports. It does not call OpenAI, accept credentials, or retain raw events.

## Why it uses a mapping file

The authenticated Compliance Logs schema can evolve independently of this project and can vary with the workspace features being used. The project therefore does not hard-code or guess an endpoint or event schema. An administrator validates the current schema in the organization’s authenticated OpenAI documentation and maps these required fields:

- `timestamp`
- `event_type`
- `surface`
- `user_id`
- optional `model`

Each value is a dot path into one JSON event. Start with `config/compliance-mapping.example.json`, then adapt it to a sanitized example from the organization.

## Run it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Convert-Enterprise-ComplianceExport.ps1 `
  -InputPath C:\ApprovedInput\compliance-export.jsonl `
  -MappingPath .\config\compliance-mapping.example.json `
  -OutputPath C:\ApprovedOutput\compliance-summary.csv
```

The output contains only:

- local calendar date;
- surface;
- event type;
- model;
- event count;
- unique-user count.

The raw user ID is held only in an in-memory set long enough to count distinct users. It is not copied to output. Prompt, response, file, tool-argument, and attachment fields are never selected.

Dimension values are stripped of control characters, length-limited, and prefixed when necessary so a value beginning with `=`, `+`, `-`, or `@` cannot become an active spreadsheet formula.

## Production collector boundary

A production live collector should run centrally, not on employee workstations. Before it is implemented, the organization must supply:

- access to the current authenticated Compliance API documentation and event schema;
- a least-privilege service identity and enterprise secret-manager integration;
- retention, employee-notice, privacy, legal, HR, and access-control decisions;
- an approved durable checkpoint and retry design;
- an explicit allowlist of surfaces/event types to retain.

The Compliance Platform’s 30-day source retention makes continuous central collection important when the organization needs longer history. This repository intentionally stops at the content-free normalization boundary until those organization-specific controls exist.
