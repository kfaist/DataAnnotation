import yaml
import logging
from pathlib import Path
from .orchestrator import Orchestrator


def load_config():
    cfg_path = Path(__file__).resolve().parent / "config" / "config.yaml"
    with open(cfg_path, "r") as f:
        return yaml.safe_load(f)


if __name__ == "__main__":
    cfg = load_config()
    logging.basicConfig(level=logging.INFO)
    orch = Orchestrator(cfg, logging.getLogger("mcp"))
    out = orch.run_daily()
    print(f"Wrote daily summary to: {out}")
