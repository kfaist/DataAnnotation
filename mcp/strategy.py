class Strategy:
    def __init__(self, config):
        self.cfg = config

    def select(self, projects, quals):
        # projects, quals are [(adapter, scope_dict)]
        worklist = []
        # Prioritize projects
        for ad, p in projects:
            worklist.append({"adapter": ad, "scope": p, "task_type": "text_generic", "budget": min(100, ad.cfg.get("daily_cap", 100))})
        # Append a few qualifications after projects to make steady progress
        if self.cfg["strategy"].get("fallback_to_qualifications", True):
            for ad, q in quals[:3]:
                worklist.append({"adapter": ad, "scope": q, "task_type": "text_generic", "budget": 20})
        # If no projects, do quals only
        if not projects:
            worklist = [{"adapter": ad, "scope": q, "task_type": "text_generic", "budget": 50} for ad, q in quals]
        return worklist
