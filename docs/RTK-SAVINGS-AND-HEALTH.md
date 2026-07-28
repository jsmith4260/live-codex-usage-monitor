# RTK savings and health

The RTK integration is an optional, local-only view of command-output compression. It does not call OpenAI, create a ChatGPT turn, use an API token, or poll an account.

## What is measured

RTK records aggregate input/output byte estimates for commands that actually run through RTK. RTK converts those byte counts into approximate token counts. The monitor reads `rtk gain --all --format json` and `rtk gain --failures`, then displays only aggregate counters and daily rows.

These values answer “how much shell output did RTK remove?” They do not measure:

- OpenAI-billed input or output tokens.
- ChatGPT message, turn, or quota consumption.
- Codex credits or API-equivalent dollars.
- Subscription or enterprise-contract savings.

The monitor never adds RTK estimates to its OpenAI credit or cost totals.

## Privacy and network behavior

- Every RTK process started by the monitor receives `RTK_TELEMETRY_DISABLED=1`.
- The monitor invokes only the local RTK executable and reads local aggregate output/history metadata.
- No command text, arguments, prompts, responses, paths, or database content are copied into monitor persistence.
- The monitor does not install, download, or update RTK at runtime.
- `Test-ZeroOutbound.ps1` scans the RTK integration along with every other production PowerShell source.

## Health states

| State | Meaning |
|---|---|
| Working - active | RTK history is readable and was updated recently. |
| Working - idle | RTK history is readable but has not changed recently. |
| Working - no savings yet | Commands are tracked, but no output reduction has been recorded. |
| Ready - no tracked commands | RTK is available, but its local history has no commands. |
| Possible bypass | Recent local shell activity is newer than RTK history by more than the allowed tolerance. A command may have run without the RTK prefix. |
| Degraded | RTK reported one or more parser failures/fallbacks. Savings can be lower because raw output may have passed through. |
| Not working / invalid local data | The RTK executable, command, or JSON result could not be used. |
| Not installed | No approved RTK executable was found. The rest of the monitor continues normally. |

`Possible bypass` is a conservative warning, not proof of a defect. A shell tool record can exist even when no compressible RTK-supported command was expected.

## Windows paths

The monitor searches an explicitly supplied `-RtkExecutablePath`, the current `PATH`, and common local installation locations. On current Windows RTK builds, aggregate history is normally under `%LOCALAPPDATA%\rtk`. Exact local paths are used for diagnostics but are not stored in the privacy-safe monitor history or displayed in aggregate tables.

Use `-DisableRtkIntegration` to suppress all RTK child processes for a launch.
