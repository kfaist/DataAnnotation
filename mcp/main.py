#!/usr/bin/env python3
"""
MCP daily entrypoint.

Default behavior: no external platforms are enabled. When PLATFORMS is empty
or contains only invalid values, write a JSON summary and exit(0).
"""
from __future__ import annotations

import json
import os
import pathlib
import sys
from datetime import datetime, timezone


def _as_bool(val: str | None, default: bool) -> bool:
    if val is None or val == "":
        return default
    return str(val).strip().lower() in {"1", "true", "t", "yes", "y", "on"}


def _now_ts() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _ensure_dir(p: pathlib.Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def main() -> int:
    # Inputs from workflow_dispatch (or schedule with defaults)
    dry_run = _as_bool(os.getenv("DRY_RUN"), default=False)
    assist_mode = _as_bool(os.getenv("ASSIST_MODE"), default=True)
    platforms_raw = (os.getenv("PLATFORMS") or "").strip()

    requested = [p.strip() for p in platforms_raw.split(",") if p.strip()]

    # By default, there are no supported platforms. Future adapters can register here
    # or via a discovery mechanism.
    SUPPORTED_PLATFORMS = set()  # e.g., {"appen", "toloka"} once adapters exist

    invalid_platforms = [p for p in requested if p not in SUPPORTED_PLATFORMS]
    has_any_valid = any(p in SUPPORTED_PLATFORMS for p in requested)

    # If no platforms were provided or all provided are invalid, we write the summary and exit 0.
    if not requested or not has_any_valid:
        summary = {
            "platforms_enabled": 0,
            "skipped_reason": "no platforms configured",
            "per_platform": [],
            "invalid_platforms": invalid_platforms,
            "DRY_RUN": dry_run,
            "ASSIST_MODE": assist_mode,
        }
        out_dir = pathlib.Path("daily_summaries")
        _ensure_dir(out_dir)
        out_file = out_dir / f"summary-{_now_ts()}.json"
        out_file.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"[MCP] Wrote summary: {out_file}")
        return 0

    # Placeholder for future platform execution path.
    summary = {
        "platforms_enabled": 0,
        "skipped_reason": "no platforms configured",
        "per_platform": [],
        "invalid_platforms": invalid_platforms,
        "DRY_RUN": dry_run,
        "ASSIST_MODE": assist_mode,
    }
    out_dir = pathlib.Path("daily_summaries")
    _ensure_dir(out_dir)
    out_file = out_dir / f"summary-{_now_ts()}.json"
    out_file.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"[MCP] Wrote summary: {out_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
