import os
import time
import random
from tenacity import retry, stop_after_attempt, wait_exponential
from playwright.sync_api import sync_playwright
from .base import PlatformAdapterBase

class AppenAdapter(PlatformAdapterBase):
    name = "appen"

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=30))
    def connect(self):
        email = os.getenv("APPEN_EMAIL")
        password = os.getenv("APPEN_PASSWORD")
        if not email or not password:
            return False, "Missing APPEN_EMAIL/APPEN_PASSWORD secrets."

        pw = sync_playwright().start()
        browser = pw.chromium.launch(headless=self.cfg.get("headless", True))
        storage_path = self.storage_state_path or ".session_states/appen_state.json"
        ctx = browser.new_context(storage_state=storage_path if os.path.exists(storage_path) else None)
        page = ctx.new_page()
        page.goto(self.cfg["base_url"], wait_until="load", timeout=60000)

        if "login" in page.url.lower() or "auth" in page.url.lower():
            # Adjust selectors if needed
            if page.query_selector('input[type="email"]'):
                page.fill('input[type="email"]', email)
            if page.query_selector('input[type="password"]'):
                page.fill('input[type="password"]', password)
            btn = page.query_selector('button:has-text("Sign in"), button:has-text("Log in"), button[type="submit"]')
            if btn:
                btn.click()
            page.wait_for_load_state("networkidle", timeout=60000)
            ctx.storage_state(path=storage_path)

        self.browser, self.page = browser, page
        return True, "Connected and session established."

    def list_active_projects(self):
        try:
            self.page.goto(self.cfg["base_url"] + "/projects", wait_until="domcontentloaded", timeout=60000)
            cards = self.page.query_selector_all('[data-testid="project-card"], .project-card, [role="article"]')
            result = []
            for c in cards:
                name_el = c.query_selector(".project-title, [data-testid='title'], h2, h3")
                status_el = c.query_selector(".status-badge, [data-status]")
                name = name_el.inner_text().strip() if name_el else "Project"
                status = status_el.inner_text().strip() if status_el else ""
                if "active" in status.lower() or status == "":
                    result.append({"id": name[:64], "name": name})
            return result
        except Exception:
            return []

    def list_qualifications(self):
        try:
            self.page.goto(self.cfg["base_url"] + "/qualifications", wait_until="domcontentloaded", timeout=60000)
            rows = self.page.query_selector_all('[data-testid="qualification-card"], .qualification-card')
            out = []
            for r in rows:
                t = r.inner_text().strip().split("\n")[0]
                out.append({"id": t[:64], "name": t})
            return out
        except Exception:
            return []

    def fetch_next_task(self, scope):
        # Placeholder navigation; adjust for real portal structure
        time.sleep(random.uniform(0.5, 1.2))
        return {"id": "sample-id", "content": "text snippet", "project": scope["name"]}

    def annotate_and_submit(self, sample, task_type, assist_mode=True):
        # Placeholder: emulate work, optionally pre-fill but not submit in assist_mode
        time.sleep(random.uniform(0.3, 0.8))
        submitted = 0 if assist_mode else 1
        return {"attempted": 1, "submitted": submitted, "notes": "assist mode pre-filled" if assist_mode else "auto-submitted", "throttled": False}
