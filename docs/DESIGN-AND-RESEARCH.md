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
- Byte-offset log tails, a privacy-safe persistent aggregate history, tray access, provenance/freshness labels, forecasts, a heatmap, model mix, and configurable budgets.
- Dated credit estimates with explicit unknown-model handling and a separate user-configured cash calculation.
- Local official-report reconciliation on the documented reporting cadence.

Comparable projects that informed these patterns:

- [CodexBar](https://github.com/steipete/CodexBar): multiple quota windows, reset countdowns, pace context, and privacy-first local monitoring.
- [Tokdash](https://github.com/JingbiaoMei/Tokdash): session/history exploration, quick time ranges, and local-first operation.
- [Codex Usage Dashboard for VS Code](https://marketplace.visualstudio.com/items?itemName=wenjun-mao.codex-usage-dashboard): archived-session discovery, quick ranges, model mix, cache share, and explicit treatment of estimates.
- [Codex Usage Monitor for VS Code](https://marketplace.visualstudio.com/items?itemName=SunYingkai.codex-usage-monitor): simple quota windows, scanned-file visibility, and configurable thresholds.
- [Claude Code Usage Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor): provenance labels, forecasts, and persistent history.
- [llm-usage-tracker](https://github.com/ninedter/llm-usage-tracker): live task cards, retention controls, and efficient file tails.
- [codex-hud](https://github.com/Jiawang1209/codex-hud): passive context, tool, and plan status without transcript display.
- [agenttop](https://github.com/vicarious11/agenttop): model/project/cache breakdowns and activity exploration.
- [tokentop](https://github.com/tokentopapp/tokentop): burn-rate, historical trends, efficiency metrics, and budget-oriented usage views.

## Ideas deliberately not adopted

- Browser-cookie or session-token scraping.
- Browser-history inspection, TLS interception, keylogging, screen capture, or Office-document inspection.
- A local HTTP dashboard service; the native WinForms application does not need an additional listening port.
- Automatic remote price updates. The checked-in rate card is dated, unknown models remain unpriced, and estimates are never presented as an invoice.
- An undocumented Compliance API client. The public Help Center describes the platform, while the current endpoint schema is available only to authenticated Enterprise/Edu customers.
- A raw-event or content database. The versioned local JSON store retains aggregate daily counters only.

## Windows UI decisions

The version 3 interface follows current Microsoft Windows guidance while remaining compatible with PowerShell 5.1 WinForms:

- a neutral layered dark foundation with a single blue interaction accent;
- semantic warning colors paired with text rather than used alone;
- Segoe UI Variable Text when installed, with Segoe UI fallback;
- a clear current-state, context, then command hierarchy;
- logical tab order, mnemonics, shortcuts, focusable standard controls, accessible names/descriptions, and DPI-aware sizing;
- text tables paired with custom charts/heatmaps so visual encodings are not the only way to read values.

Official references:

- [Windows design guidelines](https://learn.microsoft.com/en-us/windows/apps/design/guidelines-overview)
- [Windows color guidance](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/color)
- [Windows keyboard interactions](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-interactions)
- [Windows Forms accessibility properties](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/advanced/properties-on-windows-forms-controls-that-support-accessibility-guidelines)
- [Accessible text requirements](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessible-text-requirements)

## Official enterprise sources

- [Workspace analytics for ChatGPT Enterprise and Edu](https://help.openai.com/en/articles/10875114-user-analytics-for-chatgpt-enterprise-and-edu)
- [OpenAI Compliance Platform for Enterprise and Edu](https://help.openai.com/en/articles/9261474-openai-compliance-platform-for-enterprise-customers)
- [ChatGPT for Excel and Google Sheets](https://help.openai.com/en/articles/20001063-chatgpt-for-excel/)
- [ChatGPT for PowerPoint](https://help.openai.com/en/articles/20001242-chatgpt-for-powerpoint)
- [Enterprise admin quickstart](https://help.openai.com/en/articles/20001264)
