# Design and research decisions

This release compared the project with current local usage monitors and used official OpenAI guidance to define safe personal import boundaries.

## Ideas adopted

- Quick Today, 7-day, 30-day, and all-history ranges.
- Discovery of both active and archived Codex session logs.
- Quota reset countdowns and an even-pace comparison when the log supplies a window duration.
- Visible scanned-log counts.
- Privacy-safe aggregate exports.
- Separate live local data and explicitly imported personal summaries.
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
- [ccstatus](https://github.com/moond4rk/ccstatus): independent status widgets, quota bars, schema-aware parsing, configuration validation, and dense-but-readable local status presentation.

## Usage-saver research adopted in 3.3

- Keep prompt-cache benefit separate from fresh input and calculate only the full-rate versus cached-rate difference supported by the local counters and dated bundled rate card.
- Treat repeated context as a measurable break-even problem rather than automatically starting or compacting a task.
- Keep injected efficiency instructions short and stable so the policy does not undermine the caching it is intended to protect.
- Preview and allowlist Codex configuration changes; preserve the selected model, automatic compaction, unknown TOML sections, providers, and tool definitions.
- Count tool-surface breadth without displaying or persisting server/tool names.
- Detect parser/schema drift locally and retain only compatibility counters.

Official sources that informed these boundaries:

- [OpenAI prompt caching](https://openai.com/index/api-prompt-caching/)
- [Codex model-visible context guidance](https://github.com/openai/codex/blob/main/AGENTS.md#model-visible-context)
- [Codex configuration schema](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json)
- [OpenAI latest-model guidance](https://developers.openai.com/api/docs/guides/latest-model)

Third-party prompt proxies and repository bundlers were not adopted because several persist raw prompts/tool output, cache source material, add a local service, default to usage reporting, or write repository-content bundles. The native implementation keeps the monitor's no-content, no-network, and no-paid-activity boundary auditable in PowerShell.

## Ideas deliberately not adopted

- Browser-cookie or session-token scraping.
- Browser-history inspection, TLS interception, keylogging, screen capture, or Office-document inspection.
- A local HTTP dashboard service; the native WinForms application does not need an additional listening port.
- Automatic remote price updates. The checked-in rate card is dated, unknown models remain unpriced, and estimates are never presented as an invoice.
- An undocumented Compliance API client. The public Help Center describes the platform, while the current endpoint schema is available only to authenticated Enterprise/Edu customers.
- A raw-event or content database. The versioned local JSON store retains aggregate daily counters only.

## Windows UI decisions

The version 3 interface follows current Microsoft Windows guidance while remaining compatible with PowerShell 5.1 WinForms:

- a neutral layered light foundation with a single blue interaction accent and restrained semantic colors;
- semantic warning colors paired with text rather than used alone;
- Segoe UI Variable Text when installed, with Segoe UI fallback;
- a clear current-state, context, then command hierarchy;
- logical tab order, mnemonics, shortcuts, focusable standard controls, accessible names/descriptions, and DPI-aware sizing;
- text tables paired with custom charts/heatmaps so visual encodings are not the only way to read values.

The streamlined dashboard revision applies progressive disclosure and a clearer information hierarchy:

- the current Codex chat title is the primary identity, followed by the latest-turn usage and plain-language guidance;
- the default surface shows only chat-level usage, recent turns, and the selected explanation;
- integration and sanitized event diagnostics are disclosed by a dedicated **Technical details** control;
- chat titles receive the widest table column and appear beside every recent token event;
- live Codex token sources are named in the hero and tables, while import-only ChatGPT surfaces and separate API usage are labeled without combining unlike units;
- controls use sentence case, standard Windows widgets, visible keyboard focus, and consistent labels.

Version 3.4 also adopts per-user single-instance coordination. A named,
access-controlled mutex prevents duplicate interactive monitors, while a named
auto-reset event asks the existing tray/dashboard process to restore its
window. Automated QA modes remain isolated and do not participate in the
interactive-instance lock.

Official references:

- [Windows design guidelines](https://learn.microsoft.com/en-us/windows/apps/design/guidelines-overview)
- [Windows controls and patterns](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/)
- [Windows typography](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography)
- [Windows accessibility overview](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview)
- [Windows color guidance](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/color)
- [Windows keyboard interactions](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-interactions)
- [Windows Forms accessibility properties](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/advanced/properties-on-windows-forms-controls-that-support-accessibility-guidelines)
- [Accessible text requirements](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessible-text-requirements)
- [WCAG consistent identification](https://www.w3.org/WAI/WCAG22/Understanding/consistent-identification)
- [WCAG focus appearance](https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html)
- [Named EventWaitHandle synchronization](https://learn.microsoft.com/en-us/dotnet/standard/threading/eventwaithandle)
- [Windows Forms Form.Activate behavior](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.form.activate)

## Official report-format sources

- [Workspace analytics for ChatGPT Enterprise and Edu](https://help.openai.com/en/articles/10875114-user-analytics-for-chatgpt-enterprise-and-edu)
- [Chat, Work, and Codex in the ChatGPT desktop app](https://help.openai.com/en/articles/20001276/)
- [OpenAI Compliance Platform for Enterprise and Edu](https://help.openai.com/en/articles/9261474-openai-compliance-platform-for-enterprise-customers)
- [ChatGPT for Excel and Google Sheets](https://help.openai.com/en/articles/20001063-chatgpt-for-excel/)
- [ChatGPT for PowerPoint](https://help.openai.com/en/articles/20001242-chatgpt-for-powerpoint)
- [OpenAI API usage reference](https://platform.openai.com/docs/api-reference/usage)
- [Enterprise admin quickstart](https://help.openai.com/en/articles/20001264)
