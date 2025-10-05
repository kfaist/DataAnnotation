# MCP Repo

## Daily automation (default: **no external platforms**)

This repository includes a GitHub Actions workflow (`.github/workflows/mcp_daily.yml`) that can be run on a schedule or manually via **workflow_dispatch**.

**Defaults**
- No external platforms are enabled by default.
- When `PLATFORMS` is empty (the default) or contains only invalid keys, the run succeeds and writes a JSON summary at `daily_summaries/summary-<timestamp>.json` with:
  - `platforms_enabled: 0`
  - `skipped_reason: "no platforms configured"`
  - `per_platform: []`
  - `invalid_platforms: [...]`
  - and echoes `DRY_RUN` and `ASSIST_MODE`.

**Manual run (workflow_dispatch)**
- Inputs
  - `dry_run` (boolean, default `false`)
  - `assist_mode` (boolean, default `true`)
  - `PLATFORMS` (string, default `""` = none)

**Artifacts**
- Each run uploads `daily_summaries/*.json` as an artifact named `daily_summaries`.

## Enabling future platform adapters
1. Implement an adapter (e.g., under `mcp/adapters/<platform>.py`) and register its key in `SUPPORTED_PLATFORMS` inside `mcp/main.py` (or add a discovery/registry mechanism).
2. Provide any credentials in the job steps for that adapter (as repository/organization secrets or environment variables).
3. Trigger a run with `PLATFORMS` set to a comma-separated list of enabled adapter keys (e.g., `PLATFORMS="example1,example2"`).

> Note: All `APPEN_*` and `TOLOKA_*` secret references have been removed from the default workflow. Adapters that require credentials should add their own environment/secret usage locally within their steps.

---

## Test Plan and Acceptance Criteria
Include this Test Plan and Acceptance Criteria verbatim:
[paste your test plan and criteria]
