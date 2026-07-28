# Personal activity export normalizer

`Convert-Enterprise-ComplianceExport.ps1` is the compatibility-named, offline schema mapper used for a downloaded activity JSONL that has been filtered to your own account. It does not call OpenAI, accept credentials, or retain raw events.

## Why it uses a mapping file

Downloaded export schemas can evolve independently of this project and vary with the product surfaces being used. The project therefore does not hard-code or guess an endpoint or event schema. You map these required fields from the export you already downloaded:

- `timestamp`
- `event_type`
- `surface`
- `user_id`
- optional `model`

Each value is a dot path into one JSON event. Start with `config/compliance-mapping.example.json`, then adapt it to a sanitized example from your export.

## Run it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Convert-Enterprise-ComplianceExport.ps1 `
  -InputPath C:\MyExports\personal-activity-export.jsonl `
  -MappingPath .\config\compliance-mapping.example.json `
  -OutputPath C:\MyExports\personal-activity-summary.csv
```

The output contains only:

- local calendar date;
- surface;
- event type;
- model;
- event count;
- unique-user count.

The raw user ID is held only in an in-memory set long enough to verify that the input represents one person. It is not copied to output. The Personal importer rejects multiple identities. Prompt, response, file, tool-argument, and attachment fields are never selected.

Dimension values are stripped of control characters, length-limited, and prefixed when necessary so a value beginning with `=`, `+`, `-`, or `@` cannot become an active spreadsheet formula.

## Collection boundary

This personal monitor intentionally does not become a live collector. A safe personal workflow is:

- download an export through an authorized product interface;
- filter it to your own account before import;
- keep it on this computer;
- import only aggregate dimensions needed for the dashboard;
- reject any file that contains more than one identity.

The repository stops at this content-free, manual import boundary. It does not store credentials, read browser state, call private account endpoints, or establish a central employee-monitoring system.
