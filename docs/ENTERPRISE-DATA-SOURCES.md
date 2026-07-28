# Personal data-source boundary

The filename is retained for link compatibility. The product itself is a private, single-user monitor.

## Implemented recommendation

Keep the Windows monitor as an offline view of one person's local Codex activity. Additional ChatGPT coverage enters through explicit local imports filtered to that same person, never through browser traffic inspection, Office-document inspection, prompts, or keystrokes.

This preserves useful near-real-time Codex monitoring without turning the application into an administrator or employee-monitoring system.

## Supported personal sources

### 1. Downloaded usage summary

ChatGPT Enterprise and Edu Workspace Analytics provides aggregate workspace usage, including messages and GPT, tool, project, app, and skill activity. Its exports support custom date ranges up to 12 months, but the data is not real-time.

Use this source for:

- your own message totals and trends;
- your own app, tool, project, and model-family usage;
- personal monthly and weekly review.

Version 3.2 implements a single-user CSV boundary. Click **Import my data** and select one or more reports filtered to your account. Direct identifiers are used only in memory to verify the file contains no more than one identity; they are not returned to the UI.

Official reference: [Workspace analytics for ChatGPT Enterprise and Edu](https://help.openai.com/en/articles/10875114-user-analytics-for-chatgpt-enterprise-and-edu)

### 2. Downloaded personal activity export

Some Enterprise/Edu accounts can download activity sourced from the Compliance Platform. This app accepts only a local file already filtered to the individual using it.

When a user has access to an appropriate export filtered to themselves, use it for:

- their supported desktop and web ChatGPT activity;
- their supported Excel and PowerPoint add-in activity;
- personal surface, model, event-type, and date classification.

The Excel documentation states that activity may be available through compliance reporting. PowerPoint coverage depends on current product support, so the local importer reports only event surfaces actually present in the downloaded file.

Official references:

- [OpenAI Compliance Platform for Enterprise and Edu](https://help.openai.com/en/articles/9261474-openai-compliance-platform-for-enterprise-customers)
- [ChatGPT for Excel and Google Sheets](https://help.openai.com/en/articles/20001063-chatgpt-for-excel/)
- [ChatGPT for PowerPoint](https://help.openai.com/en/articles/20001242-chatgpt-for-powerpoint)

## Personal architecture

```text
Local Codex JSONL ----------------> personal Windows dashboard
Downloaded single-user CSV ------> local personal summary
Downloaded single-user JSONL ----> local content-free activity summary
```

The application has no central collector, administrator role, user directory, employee comparison, or multi-user database.

## Product phases

1. **Complete:** accurate local Codex monitoring, active/archived history, arbitrary local date ranges, privacy-safe labels/exports, and deterministic Windows tests.
2. **Complete:** single-user usage-summary CSV import with multi-user rejection and no API credentials.
3. **Complete local boundary:** mapping-driven personal activity JSONL normalization with multi-user rejection.
4. **Complete endpoint experience:** PowerShell/WinForms Control Center, persistent aggregate-only trends, official local-report reconciliation, cost parameters, provenance, and the opt-in local guard. No .NET migration is planned.
5. **Complete personal reliability:** RTK health, backup/restore, start-at-sign-in, sanitized diagnostics, and guard-continuity warnings.

## Current public-platform constraint

The current authenticated export/API schema is not public to every individual. This project therefore does not guess a route, sign in, scrape credentials, or ship a credentialed collector.

See [Compliance export normalizer](COMPLIANCE-NORMALIZER.md) for the implemented schema boundary.

## Non-goals

- Browser history scraping, TLS interception, keylogging, screen capture, or Office-document inspection.
- Tracking, comparing, ranking, or reporting on other people.
- Treating local Codex counters as billing records.
- Storing API or workspace credentials.
- Persisting prompt or response text without a separately approved compliance use case.
