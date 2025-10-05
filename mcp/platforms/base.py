from typing import List, Tuple, Optional, Dict, Any

class PlatformAdapterBase:
    name = "base"

    def __init__(self, cfg, logger, storage_state_path: Optional[str] = None):
        self.cfg = cfg
        self.logger = logger
        self.browser = None
        self.page = None
        self.storage_state_path = storage_state_path

    def connect(self) -> Tuple[bool, str]:
        raise NotImplementedError

    def list_active_projects(self) -> List[dict]:
        return []

    def list_qualifications(self) -> List[dict]:
        return []

    def fetch_next_task(self, scope: dict) -> Optional[Dict[str, Any]]:
        return None

    def annotate_and_submit(self, sample, task_type, assist_mode=True) -> dict:
        return {"attempted": 0, "submitted": 0, "notes": "not implemented", "throttled": False}
