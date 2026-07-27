# Design and research decisions

This release compared the project with current local usage monitors and used official OpenAI Enterprise/Edu guidance for enterprise data boundaries.

## Ideas adopted

- Quick Today, 7-day, 30-day, and all-history ranges.
- Discovery of both active and archived Codex session logs.
- Quota reset countdowns and an even-pace comparison when the log supplies a window duration.
- Visible scanned-log counts.
- Privacy-safe aggregate exports.
- Separate local and enterprise views.
- Deterministic fixture tests for token semantics and privacy invariants.

Comparable projects that informed these patterns:

- [CodexBar](https://github.com/steipete/CodexBar): multiple quota windows, reset countdowns, pace context, and privacy-first local monitoring.
- [Tokdash](https://github.com/JingbiaoMei/Tokdash): session/history exploration, quick time ranges, and local-first operation.
- [Codex Usage Dashboard for VS Code](https://marketplace.visualstudio.com/items?itemName=wenjun-mao.codex-usage-dashboard): archived-session discovery, quick ranges, model mix, cache share, and explicit treatment of estimates.
- [Codex Usage Monitor for VS Code](https://marketplace.visualstudio.com/items?itemName=SunYingkai.codex-usage-monitor): simple quota windows, scanned-file visibility, and configurable thresholds.

## Ideas deliberately not adopted

- Browser-cookie or session-token scraping.
- Browser-history inspection, TLS interception, keylogging, screen capture, or Office-document inspection.
- A local HTTP dashboard service; the native WinForms application does not need an additional listening port.
- Cost estimates based on checked-in model price tables. Local Codex counters are operational telemetry, not an invoice, and pricing/model aliases change independently of the application.
- An undocumented Compliance API client. The public Help Center describes the platform, while the current endpoint schema is available only to authenticated Enterprise/Edu customers.
- A local long-term database. Date-range scans remain incremental during a run and explicit CSV exports are aggregate-only.

## Official enterprise sources

- [Workspace analytics for ChatGPT Enterprise and Edu](https://help.openai.com/en/articles/10875114-user-analytics-for-chatgpt-enterprise-and-edu)
- [OpenAI Compliance Platform for Enterprise and Edu](https://help.openai.com/en/articles/9261474-openai-compliance-platform-for-enterprise-customers)
- [ChatGPT for Excel and Google Sheets](https://help.openai.com/en/articles/20001063-chatgpt-for-excel/)
- [ChatGPT for PowerPoint](https://help.openai.com/en/articles/20001242-chatgpt-for-powerpoint)
- [Enterprise admin quickstart](https://help.openai.com/en/articles/20001264)
