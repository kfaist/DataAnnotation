#!/usr/bin/env bash
set -euo pipefail

# Bootstrap MCP scaffold for DataAnnotation
# Idempotent: safe to re-run. Creates/updates minimal files required for daily autorun with a summary artifact.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

# Directories
mkdir -p data/raw data/processed data/interim scripts notebooks logs config .github/workflows artifacts
: > data/.gitkeep
: > logs/.gitkeep
: > notebooks/.gitkeep
: > config/.gitkeep

# .gitignore
cat > .gitignore << 'EOF'
# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd
*.so
*.egg-info/
*.egg
.venv/
.venv*/
.env
.env.*

# OS
.DS_Store
Thumbs.db

# Project data/artifacts
data/
!data/.gitkeep
logs/
!logs/.gitkeep
notebooks/
!notebooks/.gitkeep
artifacts/
EOF

# requirements.txt
cat > requirements.txt << 'EOF'
python-dotenv==1.0.1
pandas==2.2.2
numpy==1.26.4
requests==2.32.3
PyYAML==6.0.2
EOF

# README
cat > README.md << 'EOF'
# DataAnnotation MCP

This repository includes a minimal scaffold and GitHub Actions workflow for an autorunning "MCP Daily" process that produces a summary artifact.
- "Bootstrap MCP Repo" (one-time) writes the scaffold files via bootstrap_mcp.sh.
- "MCP Daily" runs at 09:05 UTC daily (and manually via workflow_dispatch), generating a daily-summary artifact.
- If no secrets are configured, the workflow runs in dry mode and skips side effects.

Local setup:
1) python3 -m venv .venv && source .venv/bin/activate
2) pip install -r requirements.txt
3) cp .env.example .env  # optional

See scripts/run_mcp_daily.py for details.
EOF

# .env.example
cat > .env.example << 'EOF'
# Optional settings for MCP Daily
# Set DRY_RUN=false to enable side effects (e.g., notifications)
DRY_RUN=true

# Example integration secrets (not required for dry run)
# TWILIO_ACCOUNT_SID=
# TWILIO_AUTH_TOKEN=
# TWILIO_FROM_NUMBER=
# TWILIO_TO_NUMBER=
EOF

# MCP daily script
cat > scripts/run_mcp_daily.py << 'EOF'
#!/usr/bin/env python3
import os
import json
from datetime import datetime, timezone
from pathlib import Path

def is_truthy(val: str) -> bool:
    return str(val).lower() in {"1", "true", "yes", "y", "on"}

def main():
    dry_run = is_truthy(os.getenv("DRY_RUN", "true"))

    out_dir = Path("artifacts")
    out_dir.mkdir(parents=True, exist_ok=True)
    summary_path = out_dir / "daily_summary.json"

    summary = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "dry_run": dry_run,
        "notes": [
            "MCP Daily executed.",
            "No external side effects were performed." if dry_run else "Side-effectful actions were permitted."
        ],
        "counts": {
            "new_items": 0,
            "processed_items": 0,
            "errors": 0
        }
    }

    summary_path.write_text(json.dumps(summary, indent=2))
    print(f"Wrote daily summary to {summary_path}")

if __name__ == "__main__":
    main()
EOF
chmod +x scripts/run_mcp_daily.py

# Daily workflow
cat > .github/workflows/mcp.yml << 'EOF'
name: MCP Daily

on:
  schedule:
    - cron: "5 9 * * *"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  mcp-daily:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
      - name: Run MCP Daily
        env:
          DRY_RUN: ${{ secrets.DRY_RUN || 'true' }}
        run: |
          python scripts/run_mcp_daily.py
      - name: Upload daily summary artifact
        uses: actions/upload-artifact@v4
        with:
          name: daily-summary
          path: artifacts/daily_summary.json
          if-no-files-found: error
EOF

echo "Bootstrap script completed."