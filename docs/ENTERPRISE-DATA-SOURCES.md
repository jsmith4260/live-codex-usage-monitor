# Enterprise data-source roadmap

## Recommendation

Keep the current Windows monitor as a local, read-only Codex view. Add enterprise-wide ChatGPT reporting as a separate, centrally managed data source rather than attempting to inspect browser traffic, Office documents, prompts, or keystrokes on each workstation.

This separation preserves the useful real-time Codex experience while avoiding fragile client instrumentation and unnecessary exposure of employee or customer content.

## Supported source strategy

### 1. Workspace Analytics for adoption reporting

ChatGPT Enterprise and Edu Workspace Analytics provides aggregate workspace usage, including messages and GPT, tool, project, app, and skill activity. Its exports support custom date ranges up to 12 months, but the data is not real-time.

Use this source for:

- adoption and active-user trends;
- per-user aggregate reporting where policy permits;
- app, tool, project, model-family, and skill usage;
- monthly and weekly management reports.

Official reference: [Workspace analytics for ChatGPT Enterprise and Edu](https://help.openai.com/en/articles/10875114-user-analytics-for-chatgpt-enterprise-and-edu)

### 2. Compliance Logs Platform for auditable activity

The Enterprise/Edu Compliance Platform provides workspace logs and metadata intended for audit, security, DLP, eDiscovery, and SIEM workflows. The Compliance Logs Platform retains logs for 30 days, so organizations that require longer history need a continuous central collector and an approved retention policy.

Use this source for:

- supported desktop and web ChatGPT activity;
- supported Excel and PowerPoint add-in activity;
- near-source audit events and surface classification;
- security and compliance workflows.

The Excel integration documentation explicitly states that prompts and responses are available through the Compliance API. PowerPoint log coverage depends on the workspace and current product support, so the collector should detect supported event types instead of assuming parity.

Official references:

- [OpenAI Compliance Platform for Enterprise and Edu](https://help.openai.com/en/articles/9261474-openai-compliance-platform-for-enterprise-customers)
- [ChatGPT for Excel and Google Sheets](https://help.openai.com/en/articles/20001063-chatgpt-for-excel/)
- [ChatGPT for PowerPoint](https://help.openai.com/en/articles/20001242-chatgpt-for-powerpoint)

## Proposed architecture

```text
Local Codex JSONL --------> Windows local dashboard

Workspace Analytics CSV --\
                           > Central least-privilege collector --> normalized aggregates --> enterprise dashboard
Compliance Logs Platform -/
```

The central collector should:

- run under a service identity with the minimum workspace role and API access;
- store secrets in an enterprise secret manager, never in this repository or on user workstations;
- checkpoint ingestion so 30-day compliance logs are collected continuously;
- discard prompt, response, file, and tool-argument content by default;
- retain only approved aggregate fields such as time, pseudonymous user or group, product surface, model family, message/tool counts, and reported credits or tokens;
- encrypt data in transit and at rest and log all administrative access;
- apply workspace retention, legal, HR, privacy, and employee-notice requirements before deployment.

## Product phases

1. Current release: accurate local Codex monitoring, arbitrary local date ranges, privacy-safe labels, and deterministic Windows tests.
2. Import release: read Workspace Analytics CSV exports into an enterprise dashboard without requiring API credentials in the desktop application.
3. Managed service: central Compliance Logs ingestion with surface detection for web, desktop, Excel, PowerPoint, and other supported ChatGPT clients.
4. Enterprise client: replace the PowerShell UI with a signed .NET desktop application only if centralized deployment, auto-update, accessibility certification, and IT support justify the migration.

## Non-goals

- Browser history scraping, TLS interception, keylogging, screen capture, or Office-document inspection.
- Treating local Codex counters as billing records.
- Distributing Compliance API credentials to individual endpoints.
- Persisting prompt or response text without a separately approved compliance use case.
