# Work-PC installation

Windows can mark files downloaded from a browser as originating from the
Internet. Under the common `RemoteSigned` PowerShell policy, that marker can
prevent an unsigned `.ps1` file from running even though the project is local.
An administrator can also enforce `AllSigned` or `Restricted` through Group
Policy.

## Recommended first launch

1. Download the Windows ZIP from the
   [latest GitHub release](https://github.com/jsmith4260/live-codex-usage-monitor/releases/latest).
2. Optionally verify its adjacent `.sha256` manifest.
3. Extract the complete ZIP to a normal user-writable folder.
4. Double-click `START-HERE.cmd`.

`START-HERE.cmd` uses an inline Windows PowerShell check that does not execute a
downloaded script. It first detects administrator-enforced policy. When policy
permits, it removes the Internet Zone marker from `.ps1`, `.psm1`, and `.psd1`
files under that exact extracted folder, then starts the monitor.

The bootstrap:

- does not need administrator rights;
- does not change the registry or any PowerShell execution-policy setting;
- does not contact a network service or use an OpenAI API;
- does not touch PowerShell files outside the extracted release folder; and
- does not bypass administrator-enforced `AllSigned` or `Restricted` policy.

To run only the compatibility check, open Command Prompt in the extracted
folder and run:

```batch
START-HERE.cmd --check-only
```

## If your organization requires signed scripts

If the launcher reports `AllSigned`, the GitHub release cannot run as-is
because it is checksummed but not currently Authenticode-signed. Do not lower a
managed policy. Ask IT to review and approve the source, sign the package with
your organization's trusted code-signing certificate, or provide another
approved deployment path.

If it reports `Restricted`, ask IT whether this local monitor can be approved.
The application intentionally has no policy-bypass fallback.

## Manual trusted-file recovery

For a machine using `RemoteSigned`, an administrator may prefer a manual
review-and-unblock workflow. After verifying the downloaded source and changing
to the extracted folder:

```powershell
Get-ChildItem -Recurse -File -Include *.ps1,*.psm1,*.psd1 | Unblock-File
```

Then use `START-HERE.cmd`. Calling a downloaded `.ps1` directly is not the
recommended first launch because PowerShell can block it before monitor error
handling begins.
