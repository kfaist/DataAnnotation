from datetime import datetime, timedelta
import time
import json
import os
import random

from .logging_utils import DailySummary
from .strategy import Strategy
from .platforms.appen_adapter import AppenAdapter
from .platforms.toloka_adapter import TolokaAdapter

class Orchestrator:
    def __init__(self, config, logger):
        self.config = config
        self.logger = logger
        self.strategy = Strategy(config)
        self.adapters = []
        self.summary = DailySummary()

    def _human_delay(self):
        lo, hi = self.config["runtime"].get("human_delay_ms", [300, 1800])
        time.sleep(random.uniform(lo, hi) / 1000.0)

    def run_daily(self):
        start = datetime.utcnow()
        end_by = start + timedelta(hours=self.config["runtime"]["max_daily_hours"])
        self.summary.add_reasoning("Loaded configuration and initialized session.")

        # Init adapters
        if self.config["platforms"]["appen"]["enabled"]:
            self.adapters.append(AppenAdapter(self.config["platforms"]["appen"], self.logger))
        if self.config["platforms"]["toloka"]["enabled"]:
            self.adapters.append(TolokaAdapter(self.config["platforms"]["toloka"], self.logger))

        # Connect
        connected = []
        for ad in self.adapters:
            try:
                ok, msg = ad.connect()
            except Exception as e:
                ok, msg = False, f"Error connecting: {e}"
            self.summary.add_reasoning(f"{ad.name}: {msg}")
            if ok:
                connected.append(ad)

        if not connected:
            self.summary.add_reasoning("No platforms connected; stopping.")
            return self._finish()

        # Discover active work
        projects, quals = [], []
        for ad in connected:
            try:
                p = ad.list_active_projects() or []
                q = ad.list_qualifications() or []
                self.summary.add_reasoning(f"{ad.name}: Found {len(p)} active projects, {len(q)} qualifications.")
                projects.extend([(ad, x) for x in p])
                quals.extend([(ad, x) for x in q])
            except Exception as e:
                self.summary.add_reasoning(f"{ad.name}: discovery error: {e}")

        # Build plan
        worklist = self.strategy.select(projects, quals)

        for item in worklist:
            if datetime.utcnow() >= end_by:
                self.summary.add_reasoning("Reached daily runtime budget; stopping.")
                break
            ad, scope = item["adapter"], item["scope"]
            task_type = item.get("task_type", "text_generic")
            budget = int(item.get("budget", 50))
            attempted_total = 0
            submitted_total = 0
            self.summary.add_reasoning(f"Working on {ad.name} -> {scope['name']} [{task_type}] with budget {budget}.")

            while attempted_total < budget and datetime.utcnow() < end_by:
                self._human_delay()
                if self.config["runtime"]["dry_run"]:
                    self.summary.add_reasoning(f"Dry run: would fetch/annotate next sample for {scope['name']}.")
                    attempted_total += 1
                    continue
                sample = ad.fetch_next_task(scope)
                if not sample:
                    self.summary.add_reasoning(f"{ad.name}: No more tasks in {scope['name']}.")
                    break
                res = ad.annotate_and_submit(sample, task_type, assist_mode=self.config["runtime"]["assist_mode"])
                attempted_total += max(1, int(res.get("attempted", 1)))
                submitted_total += int(res.get("submitted", 0))
                if res.get("throttled"):
                    self.summary.add_reasoning(f"{ad.name}: Throttled; backing off.")
                    time.sleep(60)

            notes = "assist mode (no auto-submit)" if self.config["runtime"]["assist_mode"] else "auto mode"
            self.summary.add_action(project=scope["name"], task_type=task_type, samples_annotated=submitted_total, notes=notes)
            self.summary.add_reasoning(f"Completed loop for {scope['name']} with attempts={attempted_total}, submitted={submitted_total}.")

        return self._finish()

    def _finish(self):
        self.summary.set_summary("Completed daily run.")
        out = self.summary.write_to_file(self.config["logging"]["export_daily_json"])
        return out
