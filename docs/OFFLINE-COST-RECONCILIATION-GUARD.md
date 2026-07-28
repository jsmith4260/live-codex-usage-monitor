# Offline cost, official reconciliation, and usage guard

These features obey two non-negotiable product requirements:

1. Personal or enterprise data never leaves the computer.
2. Monitoring creates no ChatGPT messages, turns, tokens, credits, API calls, overages, or other paid activity.

The desktop application has no runtime HTTP client. `Test-ZeroOutbound.ps1` scans every production PowerShell source file for outbound-request APIs and fails the release QA gate if one is introduced.

## Source and freshness model

The application distinguishes three fundamentally different sources:

| Source | What it can establish | Freshness |
|---|---|---|
| Existing local Codex JSONL | Near-real-time Codex activity and locally recorded quota metadata | File timestamp / live tail |
| Downloaded official usage snapshot | Official credits or token totals for reconciliation | File timestamp and official reporting cadence |
| Downloaded Workspace Analytics / Compliance export | Enterprise adoption and supported product-surface activity | Export timestamp |

Workspace Analytics is not real-time. OpenAI documents refreshes every 1–24 hours, typically 6–12 hours, with a target of up to 48 hours. The monitor labels an imported report as typical, older than typical, delayed, or stale using those intervals. It never signs in, reads browser cookies, or invokes an undocumented account endpoint to obtain fresher data.

Place a CSV or JSON snapshot in the local official-report folder, or select one in the application. The template is `config/official-usage-snapshot-template.csv`. Only these fields are retained:

- date;
- product surface;
- official credits;
- official new-input, cached-input, and output tokens.

Extra columns—including names, email addresses, account IDs, prompts, and responses—are ignored.

## Cost terminology

- **Estimated credits** use the bundled OpenAI Codex rate-card snapshot and the exact locally recorded model when a rate is known.
- **API-equivalent USD** applies the bundled standard API price for the same model. It is a comparison figure, not a ChatGPT invoice.
- **Configured cash estimate** is displayed only after the user supplies contract parameters such as dollars per credit, included credits, and fixed cycle cost.
- Unknown or unpublished model names remain **unpriced**. The monitor does not silently substitute a more expensive or cheaper model.

The bundled rate snapshot is dated and links to its official sources in `config/usage-rates.json`. Updating that file is a release action; the running application never downloads prices.

## Official reconciliation

The reconciliation view joins local daily estimated credits to the locally imported official report by date and reports:

- local estimated credits;
- official credits;
- absolute and percentage variance;
- coverage percentage;
- aligned, local-only, official-only, local-higher, or official-higher status.

A difference does not imply a billing error. Local logs can be incomplete, official reporting can lag, model mapping can be unavailable, and supported ChatGPT/Office surfaces can draw from a shared credit pool without creating local Codex JSONL.

## Usage guard

The guard is disabled by default.

- **Advisory mode** warns and enters a persistent locked state without stopping a process.
- **Enforced mode** requires the user to approve one or more exact Codex executable paths. Once the selected metric reaches the threshold and the grace period expires, the running monitor stops only processes whose full executable path exactly matches that allowlist.
- The lock is persisted locally. Re-enabling requires an affirmative in-app confirmation.

The guard never modifies a firewall, AppLocker, registry policy, browser, Office add-in, or enterprise endpoint configuration. Enforcement is active only while the monitor is running; it cannot guarantee that another launch path or another device is blocked. Organizations needing a mandatory enterprise control should use supported workspace spending controls and an approved endpoint-management policy.

Because process termination can interrupt active work, enforced mode should use a visible warning and grace interval. QA uses injected fake process objects and never terminates a real Codex process.

## Official references

- [OpenAI Codex rate card](https://help.openai.com/en/articles/20001106-codex-rate-card)
- [OpenAI API model price comparison](https://developers.openai.com/api/docs/models/compare)
- [Workspace analytics for ChatGPT Enterprise and Edu](https://help.openai.com/en/articles/10875114)
- [OpenAI Compliance Platform](https://help.openai.com/en/articles/9261474-openai-compliance-platform-for-enterprise-customers)
- [Flexible credits for ChatGPT plans](https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-pluspro)
- [Flexible pricing for ChatGPT Enterprise](https://help.openai.com/en/articles/11487671-flexible-pricing-for-chatgpt-enterprise-plans)
