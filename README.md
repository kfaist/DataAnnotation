MCP Annotation Agent (GitHub Actions + Playwright)

What it does
- Logs into supported annotation portals via UI automation (Playwright).
- Discovers active projects; prioritizes work; falls back to qualifications.
- Runs up to 5 hours daily; outputs a JSON daily summary.

Quick start
1) Add repository secrets (Settings > Secrets and variables > Actions):
   - APPEN_EMAIL, APPEN_PASSWORD
   - TOLOKA_EMAIL, TOLOKA_PASSWORD
2) Adjust schedule in .github/workflows/mcp.yml (cron is UTC).
3) First runs are dry-run + assist mode (no submissions). Set runtime.dry_run=false to enable real actions.

Local dry run (optional)
- python -m venv .venv && source .venv/bin/activate
- pip install -r requirements.txt
- python -m playwright install --with-deps
- export APPEN_EMAIL=... APPEN_PASSWORD=... TOLOKA_EMAIL=... TOLOKA_PASSWORD=...
- python mcp/main.py

Notes
- UI selectors in adapters are placeholders; adjust to your portals’ DOM.
- If 2FA is enforced, use a self-hosted runner or persist Playwright storage_state via workflow artifact (already configured).
- Respect ToS. Keep assist_mode=true unless you have explicit permission for auto-submission.
