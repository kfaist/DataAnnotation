#!/usr/bin/env bash
set -euo pipefail

# Create directories
mkdir -p mcp/config mcp/platforms mcp/annotators .github/workflows daily_summaries logs .session_states

# .gitignore
cat > .gitignore << 'EOF'
.venv/
__pycache__/
*.pyc
logs/
.session_states/
*.log
.playwright/
daily_summaries/*.json
EOF

# requirements.txt
cat > requirements.txt << 'EOF'
playwright==1.47.2
pydantic==2.8.2
python-dateutil==2.9.0.post0
tenacity==8.3.0
pyyaml==6.0.2
EOF
