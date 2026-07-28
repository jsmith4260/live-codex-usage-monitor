# Windows reliability and distribution

Version 3.4 closes the final application productization phase without changing
the local-only data boundary.

## Single-instance behavior

Normal interactive launches are coordinated per Windows user and sign-in
session. The first monitor owns a named mutex and a named auto-reset activation
event. A later launch signals that event and exits; the running monitor restores
its dashboard from the tray and activates the visible dashboard or its current
modal dialog.

The synchronization object names contain a short SHA-256 fingerprint derived
from the current Windows security identifier. The identifier itself is not
stored, displayed, logged, or transmitted. Access-control entries restrict the
objects to the current Windows identity.

Automated smoke tests bypass single-instance enforcement. The
`-AllowMultipleInstances` switch exists for controlled troubleshooting and test
work; normal launchers do not use it.

If Windows synchronization setup is unavailable, the monitor continues and
shows a sanitized startup warning. It does not persist the exception message or
fall back to an online service.

## Launchers

The two `.cmd` launchers start Windows PowerShell in STA mode with its console
window hidden. The dashboard or mini view remains the visible application
surface. Starting the launcher again requests the existing window instead of
creating a duplicate monitor.

## GitHub Releases

Pushing a semantic tag that exactly matches `v` plus the checked-in `VERSION`
starts the release workflow. The Windows runner:

1. validates the tag/version pair;
2. runs PSScriptAnalyzer with zero allowed errors;
3. runs the deterministic local QA suite and zero-outbound gate;
4. builds the versioned ZIP and SHA-256 manifest;
5. creates stable-name copies for the permanent README download URL; and
6. creates or safely updates the GitHub Release and its four assets.

The release workflow receives only GitHub's repository-scoped temporary token.
It is development infrastructure and is not present in the shipped monitor.
The running monitor remains completely offline.

## Issue privacy

Structured bug and feature forms remind contributors not to upload logs,
prompts, responses, identifiers, credentials, personal paths, or unsanitized
screenshots. Bug reports point users to the existing sanitized diagnostic
export. Feature requests must affirm the local-only, zero-monitoring-cost, and
single-user product contract.
