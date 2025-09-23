# /opt/shim/app.py
import os
import json
import time
import uuid
import logging
from typing import Dict, Any, Optional, List

import httpx
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request, Depends, Security
from fastapi.security import APIKeyHeader, APIKeyQuery
from pathlib import Path

log = logging.getLogger("shim")
logging.basicConfig(level=logging.INFO)

COMFY_HOST = os.getenv("COMFY_HOST", "127.0.0.1")
COMFY_PORT = int(os.getenv("COMFY_PORT", "8188"))
COMFY_API_URL = os.getenv("COMFY_API_URL", f"http://127.0.0.1:{COMFY_PORT}")
DEFAULT_WORKFLOW_PATH = os.getenv("SHIM_WORKFLOW_PATH", "/workspace/ComfyUI/user/default/workflows/_auto_default.json")
DEFAULT_WORKFLOW = Path(DEFAULT_WORKFLOW_PATH).resolve()

_WORKFLOW_ROOT_ENV = os.getenv("SHIM_WORKFLOW_ROOT", "")
_ADDITIONAL_ROOTS_ENV = os.getenv("SHIM_ADDITIONAL_WORKFLOW_ROOTS", "")
WORKFLOW_ROOTS: List[Path] = []
for raw in (_WORKFLOW_ROOT_ENV.split(":") if _WORKFLOW_ROOT_ENV else []):
    raw = raw.strip()
    if raw:
        WORKFLOW_ROOTS.append(Path(raw).resolve())
if not WORKFLOW_ROOTS:
    WORKFLOW_ROOTS.append(DEFAULT_WORKFLOW.parent)
for raw in (_ADDITIONAL_ROOTS_ENV.split(":") if _ADDITIONAL_ROOTS_ENV else []):
    raw = raw.strip()
    if raw:
        WORKFLOW_ROOTS.append(Path(raw).resolve())
_seen_roots = set()
_unique_roots: List[Path] = []
for root in WORKFLOW_ROOTS:
    key = str(root)
    if key not in _seen_roots:
        _seen_roots.add(key)
        _unique_roots.append(root)
WORKFLOW_ROOTS = _unique_roots

SHIM_API_KEY = os.getenv("SHIM_API_KEY")
REQUIRE_API_KEY = os.getenv("SHIM_REQUIRE_API_KEY", "1").strip().lower() not in {"0", "false", "no"}
if REQUIRE_API_KEY and not SHIM_API_KEY:
    log.warning("SHIM_REQUIRE_API_KEY=1 but SHIM_API_KEY is not set; requests will be rejected.")
log.info("Allowed workflow roots: %s", ", ".join(str(p) for p in WORKFLOW_ROOTS))
CLIENT_TIMEOUT = float(os.getenv("SHIM_HTTP_TIMEOUT", "120"))
POLL_INTERVAL = float(os.getenv("SHIM_POLL_INTERVAL", "0.75"))
DEFAULT_WAIT_LIMIT = float(os.getenv("SHIM_MAX_WAIT_SECONDS", "600"))

app = FastAPI(title="WAN 2.2 Shim", version="1.0.0")

# -------------------------------
# Helpers
# -------------------------------
def _now_ms() -> int:
    return int(time.time() * 1000)

async def _comfy_get(client: httpx.AsyncClient, path: str) -> Dict[str, Any]:
    r = await client.get(f"{COMFY_API_URL.rstrip('/')}{path}")
    r.raise_for_status()
    if r.headers.get("content-type", "").startswith("application/json"):
        return r.json()
    return {}

async def _comfy_post(client: httpx.AsyncClient, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    r = await client.post(f"{COMFY_API_URL.rstrip('/')}{path}", json=payload)
    r.raise_for_status()
    return r.json()

async def _queue_prompt(client: httpx.AsyncClient, prompt: Dict[str, Any], client_id: str) -> str:
    payload = {"prompt": prompt, "client_id": client_id}
    data = await _comfy_post(client, "/prompt", payload)
    pid = data.get("prompt_id") or data.get("promptId")
    if not pid:
        raise HTTPException(500, "Comfy did not return a prompt_id")
    return pid

async def _history_for(client: httpx.AsyncClient, prompt_id: str) -> Optional[Dict[str, Any]]:
    try:
        return await _comfy_get(client, f"/history/{prompt_id}")
    except Exception:
        return None

async def _queue_state(client: httpx.AsyncClient) -> Dict[str, Any]:
    return await _comfy_get(client, "/queue")

def _prompt_in_queue(queue: Dict[str, Any], prompt_id: str) -> bool:
    buckets = ("queue_running", "queue_pending", "running", "queue")
    for bucket in buckets:
        entries = queue.get(bucket, [])
        for entry in entries:
            if isinstance(entry, dict) and (entry.get("id") == prompt_id or entry.get("prompt_id") == prompt_id):
                return True
            if isinstance(entry, (list, tuple)) and prompt_id in entry:
                return True
    return False


def _load_workflow(path: str) -> Dict[str, Any]:
    resolved = _resolve_workflow_path(path)
    try:
        with resolved.open("r", encoding="utf-8") as f:
            obj = json.load(f)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(400, f"Workflow JSON invalide: {e}")
    if isinstance(obj, dict) and ("prompt" in obj or "workflow" in obj or "nodes" in obj):
        if "prompt" in obj:
            return obj["prompt"]
        if "workflow" in obj:
            return obj["workflow"]
        return obj
    raise HTTPException(400, "Workflow non supporté (attendu dict Comfy API ou export UI).")

def _normalize_bool(v: Optional[str]) -> Optional[bool]:
    if v is None:
        return None
    s = str(v).strip().lower()
    if s in ("1", "true", "yes", "on"): return True
    if s in ("0", "false", "no", "off"): return False
    return None

def _path_is_allowed(path: Path) -> bool:
    for root in WORKFLOW_ROOTS:
        try:
            path.relative_to(root)
            return True
        except ValueError:
            continue
    return False


def _resolve_workflow_path(raw_path: str) -> Path:
    if not raw_path:
        raise HTTPException(400, "Workflow introuvable: chemin vide")
    candidate = Path(raw_path)
    search: List[Path] = []
    if candidate.is_absolute():
        search.append(candidate)
    else:
        for root in WORKFLOW_ROOTS:
            search.append(root / candidate)
    if not search:
        search.append(candidate)
    denied = True
    for item in search:
        resolved = item.resolve()
        if not _path_is_allowed(resolved):
            continue
        denied = False
        if resolved.exists():
            return resolved
    if denied:
        raise HTTPException(403, f"Workflow path non autorisé: {raw_path}")
    raise HTTPException(400, f"Workflow introuvable: {raw_path}")


api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)
api_key_query = APIKeyQuery(name="api_key", auto_error=False)


async def require_api_key(header_key: Optional[str] = Security(api_key_header), query_key: Optional[str] = Security(api_key_query)) -> None:
    if not REQUIRE_API_KEY:
        return
    if not SHIM_API_KEY:
        raise HTTPException(500, "Shim API key not configured")
    provided = header_key or query_key
    if not provided or provided != SHIM_API_KEY:
        raise HTTPException(401, "Invalid or missing API key")

# -------------------------------
# Routes
# -------------------------------
@app.get("/health")
async def health(_: None = Depends(require_api_key)):
    async with httpx.AsyncClient(timeout=CLIENT_TIMEOUT) as client:
        try:
            data = await _comfy_get(client, "/system_stats")
            return {"ok": True, "comfy": True, "stats": data}
        except Exception:
            return {"ok": True, "comfy": False}

@app.post("/run")
async def run(
    request: Request,
    workflow: Optional[UploadFile] = File(None),
    workflow_path: Optional[str] = Form(None),
    wait: Optional[str] = Form("true"),
    wait_timeout_s: Optional[float] = Form(None),
    client_id: Optional[str] = Form(None),
    _: None = Depends(require_api_key),
):
    """
    Lance un workflow Comfy. Fournir:
      - `workflow` (upload JSON) OU `workflow_path` (chemin sur le pod) OU rien (utilise DEFAULT_WORKFLOW)
      - `wait` = true/false (attendre la complétion)
    """
    if workflow is not None:
        content = await workflow.read()
        try:
            prompt = json.loads(content.decode("utf-8"))
        except Exception as e:
            raise HTTPException(400, f"JSON invalide: {e}")
    else:
        chosen = workflow_path or str(DEFAULT_WORKFLOW)
        prompt = _load_workflow(chosen)

    cid = client_id or f"shim-{uuid.uuid4().hex[:12]}"

    async with httpx.AsyncClient(timeout=CLIENT_TIMEOUT) as client:
        prompt_id = await _queue_prompt(client, prompt, cid)

        w = _normalize_bool(wait)
        try:
            max_wait = float(wait_timeout_s) if wait_timeout_s is not None else DEFAULT_WAIT_LIMIT
        except (TypeError, ValueError):
            raise HTTPException(400, "wait_timeout_s invalide")
        if w is False or max_wait <= 0:
            return {"job_id": prompt_id, "status": "queued"}

        deadline_ms = _now_ms() + int(max_wait * 1000)
        timeout_detail = {"message": f"Timeout en attente de Comfy ({max_wait:g}s)", "job_id": prompt_id}
        while True:
            hist = await _history_for(client, prompt_id)
            if hist and prompt_id in hist:
                entry = hist[prompt_id]
                status = entry.get("status") or ("completed" if entry.get("outputs") else "running")
                outs = entry.get("outputs", {})
                return {"job_id": prompt_id, "status": status, "outputs": outs}

            if _now_ms() >= deadline_ms:
                raise HTTPException(status_code=504, detail=timeout_detail)

            queue_state = await _queue_state(client)
            if not _prompt_in_queue(queue_state, prompt_id) and _now_ms() >= deadline_ms:
                raise HTTPException(status_code=504, detail=timeout_detail)

            await asyncio_sleep(POLL_INTERVAL)

@app.get("/status/{job_id}")
async def status(job_id: str, _: None = Depends(require_api_key)):
    async with httpx.AsyncClient(timeout=CLIENT_TIMEOUT) as client:
        hist = await _history_for(client, job_id)
        if hist and job_id in hist:
            entry = hist[job_id]
            outs = entry.get("outputs", {})
            if entry.get("status"):
                stat = entry["status"]
            elif outs:
                stat = "completed"
            else:
                stat = "running"
            return {"job_id": job_id, "status": stat, "outputs": outs}

        queue_state = await _queue_state(client)
        mapped_buckets = {
            "queue_running": "running",
            "running": "running",
            "queue_pending": "queued",
            "queue": "queued",
        }
        for bucket, status_name in mapped_buckets.items():
            for entry in queue_state.get(bucket, []):
                if isinstance(entry, dict) and (entry.get("id") == job_id or entry.get("prompt_id") == job_id):
                    return {"job_id": job_id, "status": status_name}
                if isinstance(entry, (list, tuple)) and job_id in entry:
                    return {"job_id": job_id, "status": status_name}

    raise HTTPException(404, "job_id not found")

# petit wrapper pour await sleep dans la boucle /run
import asyncio
async def asyncio_sleep(s: float):  # noqa
    await asyncio.sleep(s)
