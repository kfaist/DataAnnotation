import os
import json
from datetime import datetime

class DailySummary:
    def __init__(self):
        self.reasoning_steps = []
        self.annotation_actions = []
        self.summary = ""

    def add_reasoning(self, msg: str):
        self.reasoning_steps.append(msg)

    def add_action(self, project, task_type, samples_annotated, notes=None, attempted=None):
        self.annotation_actions.append({
            "project": project,
            "task_type": task_type,
            "samples_annotated": int(samples_annotated),
            "attempted": int(attempted if attempted is not None else samples_annotated),
            "notes": notes or ""
        })

    def set_summary(self, text: str):
        self.summary = text

    def to_json(self):
        return {
            "reasoning_steps": self.reasoning_steps,
            "annotation_actions": self.annotation_actions,
            "summary": self.summary
        }

    def write_to_file(self, out_dir: str):
        os.makedirs(out_dir, exist_ok=True)
        fname = os.path.join(out_dir, f"summary-{datetime.utcnow().date()}.json")
        with open(fname, "w") as f:
            json.dump(self.to_json(), f, indent=2)
        return fname
