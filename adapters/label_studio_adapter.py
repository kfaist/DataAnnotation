import os
import time
import random
import logging
from typing import Dict, Any, List
import requests


class LabelStudioAdapter:
    """
    Adapter for integrating with Label Studio via REST API.
    """

    def __init__(self):
        # base settings from env
        self.base_url = os.environ.get("LABEL_STUDIO_URL", "").rstrip("/")
        self.api_token = os.environ.get("LABEL_STUDIO_API_TOKEN")
        self.email = os.environ.get("LABEL_STUDIO_EMAIL")
        self.password = os.environ.get("LABEL_STUDIO_PASSWORD")
        self.project_id = os.environ.get("LABEL_STUDIO_PROJECT_ID")
        if self.project_id is not None:
            try:
                self.project_id = int(self.project_id)
            except ValueError:
                raise ValueError("LABEL_STUDIO_PROJECT_ID must be an integer")
        # dynamic label mapping
        self.from_name = os.environ.get("LABEL_STUDIO_FROM_NAME", "label")
        self.to_name = os.environ.get("LABEL_STUDIO_TO_NAME", "text")
        self.session = None
        # http summary
        self.http_summary = {"last_status": None, "counts": {"2xx": 0, "4xx": 0, "5xx": 0}}

    def _update_http_summary(self, status: int):
        self.http_summary["last_status"] = status
        if 200 <= status < 300:
            self.http_summary["counts"]["2xx"] += 1
        elif 400 <= status < 500:
            self.http_summary["counts"]["4xx"] += 1
        elif 500 <= status < 600:
            self.http_summary["counts"]["5xx"] += 1

    def authenticate(self) -> requests.Session:
        """
        Authenticate against Label Studio and return a requests.Session.
        Tries token authentication first, then email/password login.
        """
        if not self.base_url:
            raise ValueError("LABEL_STUDIO_URL is not set")
        session = requests.Session()
        # token auth
        if self.api_token:
            session.headers.update({"Authorization": f"Token {self.api_token}"})
        else:
            if not (self.email and self.password):
                raise ValueError("Must set LABEL_STUDIO_API_TOKEN or LABEL_STUDIO_EMAIL and LABEL_STUDIO_PASSWORD")
            login_payload = {"email": self.email, "password": self.password}
            # attempt /user/login (v1) fallback to /api/user/login (v2)
            for login_path in ["/api/user/login", "/user/login"]:
                try:
                    resp = session.post(f"{self.base_url}{login_path}", json=login_payload, timeout=15)
                    self._update_http_summary(resp.status_code)
                    if resp.ok:
                        break
                    # continue to next path if 404
                    if resp.status_code == 404:
                        continue
                    resp.raise_for_status()
                except requests.RequestException as e:
                    raise RuntimeError(f"Label Studio login failed: {e}") from e
        # validate current user
        try:
            resp = session.get(f"{self.base_url}/api/current-user", timeout=15)
            self._update_http_summary(resp.status_code)
            if resp.status_code == 401 or resp.status_code == 403:
                raise RuntimeError(f"Authentication failed with status {resp.status_code}")
            resp.raise_for_status()
        except requests.RequestException as e:
            raise RuntimeError(f"Label Studio auth validation failed: {e}") from e
        self.session = session
        return session

    def _safe_request(self, method: str, url: str, **kwargs) -> requests.Response:
        """
        Perform HTTP request with retry on timeouts and 5xx errors.
        """
        backoff = 1.0
        for attempt in range(3):
            try:
                resp = self.session.request(method, url, timeout=20, **kwargs)
                self._update_http_summary(resp.status_code)
                # abort on auth errors
                if resp.status_code in (401, 403):
                    raise RuntimeError(f"Request unauthorized with status {resp.status_code}")
                if resp.status_code >= 500:
                    # raise and retry
                    raise requests.HTTPError(f"Server error {resp.status_code}")
                return resp
            except (requests.Timeout, requests.HTTPError) as e:
                if attempt < 2:
                    time.sleep(backoff + random.random() * 0.5)
                    backoff *= 2
                    continue
                raise
        raise RuntimeError("Max retries exceeded")

    def discover_tasks(self, limit: int = 50) -> List[Dict[str, Any]]:
        """
        Discover up to `limit` tasks in the configured project.
        Returns list of {id, data}.
        """
        if not self.session:
            raise RuntimeError("Not authenticated")
        if not self.project_id:
            raise ValueError("LABEL_STUDIO_PROJECT_ID is not set")
        tasks_url = f"{self.base_url}/api/projects/{self.project_id}/tasks"
        params = {
            "page_size": limit,
            "ordering": "-created_at",
        }
        resp = self._safe_request("get", tasks_url, params=params)
        try:
            data = resp.json()
        except Exception as e:
            raise RuntimeError(f"Failed to parse task list: {e}")
        tasks_list: List[Dict[str, Any]] = []
        items = data.get("tasks") if isinstance(data, dict) else data
        for item in items:
            task_id = item.get("id")
            task_data = item.get("data", {})
            if task_id is not None:
                tasks_list.append({"id": task_id, "data": task_data})
            if len(tasks_list) >= limit:
                break
        return tasks_list

    def prefill_annotation(self, task: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Produce a deterministic annotation for a given task.
        For a text/choices project: choose "Positive" if the text contains
        good/happy/love, else "Negative". If choices UI not available, fallback to text.
        """
        data = task.get("data", {})
        text_value: str | None = None
        if isinstance(data, dict):
            for v in data.values():
                if isinstance(v, str):
                    text_value = v
                    break
        if text_value is None:
            text_value = ""
        lower = text_value.lower()
        label = "Positive" if any(word in lower for word in ["good", "happy", "love"]) else "Negative"
        result = [
            {
                "from_name": self.from_name,
                "to_name": self.to_name,
                "type": "choices",
                "value": {"choices": [label]},
            }
        ]
        return result

    def submit_annotation(self, task_id: int, result: List[Dict[str, Any]]) -> None:
        """
        Submit an annotation to the task.
        """
        if not self.session:
            raise RuntimeError("Not authenticated")
        url = f"{self.base_url}/api/tasks/{task_id}/annotations"
        payload = {"result": result}
        resp = self._safe_request("post", url, json=payload)
        if not (200 <= resp.status_code < 300):
            raise RuntimeError(f"Annotation submission failed with status {resp.status_code}")

    def run(self, assist_mode: bool, max_submissions: int) -> Dict[str, Any]:
        """
        Orchestrate discovery and (optionally) submission of annotations.
        Returns a summary dict used by the orchestrator.
        """
        summary: Dict[str, Any] = {
            "name": "labelstudio",
            "login_ok": False,
            "project_id": self.project_id,
            "tasks_discovered": 0,
            "tasks_prefilled": 0,
            "submissions_attempted": 0,
            "submissions_succeeded": 0,
            "errors": [],
            "http_summary": self.http_summary,
        }
        try:
            self.authenticate()
            summary["login_ok"] = True
        except Exception as e:
            summary["errors"].append(f"Authentication error: {e}")
            return summary
        try:
            tasks = self.discover_tasks(limit=max_submissions if not assist_mode else 50)
            summary["tasks_discovered"] = len(tasks)
        except Exception as e:
            summary["errors"].append(f"Task discovery error: {e}")
            return summary
        for task in tasks:
            try:
                result = self.prefill_annotation(task)
                summary["tasks_prefilled"] += 1
                if not assist_mode:
                    summary["submissions_attempted"] += 1
                    if summary["submissions_attempted"] > max_submissions:
                        break
                    self.submit_annotation(task["id"], result)
                    summary["submissions_succeeded"] += 1
                time.sleep(0.1 + random.random() * 0.1)
            except Exception as e:
                summary["errors"].append(f"Task {task.get('id')} error: {e}")
        return summary
