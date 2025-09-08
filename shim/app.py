# /opt/shim/app.py
import os, json, time, uuid, re, pathlib, logging
from typing import Optional, List, Dict, Any

import httpx
from fastapi import FastAPI, UploadFile, File, Form, Request, HTTPException
from fastapi.responses import JSONResponse

log = logging.getLogger("shim")
logging.basicConfig(level=logging.INFO)

COMFY_HOST = os.getenv("COMFY_HOST", "127.0.0.1")
COMFY_PORT = int(os.getenv("COMFY_PORT", "8188"))
COMFY_API_URL = os.getenv("COMFY_API_URL", f"http://127.0.0.1:{COMFY_PORT}")

# Fallback historique (évite 500 si rien n’est configuré)
FALLBACK_WORKFLOW = "/workspace/ComfyUI/user/default/workflows/Wan22_I2V_Native_3_stage.json"

# Emplacements de config "à chaud" (éditables via Jupyter)
CONFIG_PATHS = [
    "/workspace/shim/WORKFLOW_PATH.txt",
    "/opt/shim/WORKFLOW_PATH.txt",
]

JOBS: Dict[str, Dict[str, Any]] = {}
app = FastAPI(title="ComfyUI I2V Shim", version="0.3.1")


# ---------- helpers ----------

def get_template_path() -> str:
    """
    Résout le chemin du template dans l’ordre suivant:
      1) Fichier /workspace/shim/WORKFLOW_PATH.txt (ou /opt/shim/WORKFLOW_PATH.txt)
      2) Variable d’environnement SHIM_WORKFLOW_PATH
      3) Variable d’environnement DEFAULT_WORKFLOW
      4) FALLBACK_WORKFLOW (safe)
    """
    for p in CONFIG_PATHS:
        try:
            if os.path.isfile(p):
                content = pathlib.Path(p).read_text(encoding="utf-8").strip()
                if content:
                    return content
        except Exception:
            pass
    return (
        os.getenv("SHIM_WORKFLOW_PATH")
        or os.getenv("DEFAULT_WORKFLOW")
        or FALLBACK_WORKFLOW
    )


def _safe_ext(name: str) -> str:
    ext = os.path.splitext(name or "")[1].lower()
    return ext if re.fullmatch(r"\.[a-z0-9]{1,5}", ext or "") else ".png"


def _safe_name(original: Optional[str]) -> str:
    return f"input_{uuid.uuid4().hex}{_safe_ext(original or '')}"


def _walk_replace(x, mapping: Dict[str, Any]):
    if isinstance(x, dict):
        return {k: _walk_replace(v, mapping) for k, v in x.items()}
    if isinstance(x, list):
        return [_walk_replace(v, mapping) for v in x]
    if isinstance(x, str) and x in mapping:
        return mapping[x]
    return x


def _normalize_node_dict(d: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Normalise une entrée de nœud en { 'class_type': str, 'inputs': dict }.
    Accepte 'class_type' ou 'type' comme alias.
    """
    if not isinstance(d, dict):
        return None
    ct = d.get("class_type") or d.get("type")
    if not ct:
        return None
    return {"class_type": ct, "inputs": d.get("inputs", {})}


def _to_api_prompt(obj) -> Dict[str, Any]:
    """
    Convertit en API Prompt:
      - dict déjà API prompt (valeurs avec class_type/type + inputs)  ✔︎
      - list de nœuds [{'id', 'class_type'/ 'type', 'inputs'}, ...]  ✔︎
    N’essaie PAS de convertir un workflow UI (graph éditeur).
    """
    # dict ?
    if isinstance(obj, dict):
        values = list(obj.values())
        if values and all(isinstance(v, dict) for v in values):
            normalized = {}
            for k, v in obj.items():
                nv = _normalize_node_dict(v)
                if nv is None:
                    raise HTTPException(
                        status_code=400,
                        detail="Template dict trouvé mais certaines entrées n’ont pas 'class_type'/'type' et 'inputs' (probable workflow UI).",
                    )
                normalized[str(k)] = nv
            return normalized
        raise HTTPException(
            status_code=400,
            detail="Template dict non conforme (probable workflow UI).",
        )

    # list ?
    if isinstance(obj, list):
        api: Dict[str, Any] = {}
        for idx, node in enumerate(obj, 1):
            if isinstance(node, dict):
                nv = _normalize_node_dict(node)
                if nv is None:
                    raise HTTPException(
                        status_code=400,
                        detail="Élément de liste non conforme (pas de 'class_type'/'type').",
                    )
                nid = str(node.get("id", idx))
                api[nid] = nv
            elif isinstance(node, (list, tuple)) and len(node) == 2 and isinstance(node[1], dict):
                nv = _normalize_node_dict(node[1])
                if nv is None:
                    raise HTTPException(
                        status_code=400,
                        detail="Élément (pair) de liste non conforme (pas de 'class_type'/'type').",
                    )
                nid = str(node[0])
                api[nid] = nv
            else:
                raise HTTPException(
                    status_code=400,
                    detail="Élément de liste non pris en charge pour un API Prompt.",
                )
        if not api:
            raise HTTPException(status_code=400, detail="Liste vide/non valide pour un API Prompt.")
        return api

    raise HTTPException(status_code=400, detail="Template JSON non supporté (ni dict, ni liste).")


def _load_api_prompt_template(path: str) -> Dict[str, Any]:
    if not os.path.isfile(path):
        raise HTTPException(status_code=500, detail=f"Template introuvable: {path}")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=500, detail=f"Template JSON invalide: {e}")
    api = _to_api_prompt(data)
    return api


async def _comfy_upload_image(client: httpx.AsyncClient, image_bytes: bytes, filename: str) -> str:
    files = {"image": (filename, image_bytes, "application/octet-stream")}
    params = {"type": "input", "subfolder": ""}
    r = await client.post(f"{COMFY_API_URL}/upload/image", files=files, params=params)
    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=f"ComfyUI upload failed: HTTP {r.status_code} - {r.text}")
    # {"name": "...", "subfolder": "", "type": "input"}
    return filename


async def _comfy_submit_prompt(client: httpx.AsyncClient, prompt_graph: Dict[str, Any]) -> str:
    client_id = uuid.uuid4().hex
    payload = {"client_id": client_id, "prompt": prompt_graph}
    r = await client.post(f"{COMFY_API_URL}/prompt", json=payload)
    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=f"ComfyUI prompt submission failed: HTTP {r.status_code} - {r.text}")
    data = r.json()
    prompt_id = data.get("prompt_id") or data.get("id") or data.get("name")
    if not prompt_id:
        raise HTTPException(status_code=502, detail=f"ComfyUI did not return a prompt_id: {data}")
    JOBS[prompt_id] = {"client_id": client_id, "created_at": time.time(), "status": "queued"}
    return prompt_id


async def _comfy_queue(client: httpx.AsyncClient) -> Dict[str, Any]:
    r = await client.get(f"{COMFY_API_URL}/queue")
    return r.json() if r.status_code == 200 else {}


async def _comfy_history(client: httpx.AsyncClient, job_id: str) -> Dict[str, Any]:
    r = await client.get(f"{COMFY_API_URL}/history/{job_id}")
    return r.json() if r.status_code == 200 else {}


def _outputs_from_history(history: Dict[str, Any]) -> List[Dict[str, Any]]:
    # Accepte { "history": { id: {...} } } ou { id: {...} }
    h = history.get("history", history)
    if not isinstance(h, dict) or not h:
        return []
    entry = next(iter(h.values()))
    outputs = []
    for node_out in (entry.get("outputs") or {}).values():
        for it in (node_out.get("images") or []) + (node_out.get("videos") or []):
            fn = it.get("filename"); sub = it.get("subfolder",""); typ = it.get("type","output")
            if fn:
                outputs.append({
                    "filename": fn,
                    "subfolder": sub,
                    "type": typ,
                    "url": f"{COMFY_API_URL}/view?filename={fn}&subfolder={sub}&type={typ}",
                })
    return outputs


# ---------- API ----------

@app.get("/")
async def root():
    path = get_template_path()
    exists = os.path.isfile(path)
    return {"service": "comfyui-shim", "comfy_api": COMFY_API_URL, "workflow": path, "exists": exists}


@app.post("/config/workflow")
async def set_workflow(path: str = Form(...)):
    """
    Modifie le chemin de workflow pour CE process (sans redéploiement) en écrivant
    /workspace/shim/WORKFLOW_PATH.txt
    """
    if not path:
        raise HTTPException(status_code=400, detail="path manquant")
    pathlib.Path("/workspace/shim").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/workspace/shim/WORKFLOW_PATH.txt").write_text(path, encoding="utf-8")
    return {"ok": True, "workflow": path}


@app.post("/i2v")
async def create_i2v(
    request: Request,
    image: Optional[UploadFile] = File(None),
    image_url: Optional[str] = Form(None),
    prompt: Optional[str] = Form(None),
    negative: Optional[str] = Form(None),
    fps: Optional[int] = Form(None),
    duration_s: Optional[float] = Form(None),
    seed: Optional[int] = Form(None),
    guidance: Optional[float] = Form(None),
    steps: Optional[int] = Form(None),
    sampler: Optional[str] = Form(None),
    width: Optional[int] = Form(None),
    height: Optional[int] = Form(None),
):
    # JSON body support
    if request.headers.get("content-type","").startswith("application/json"):
        body = await request.json()
        image_url = body.get("image_url")
        prompt = body.get("prompt")
        negative = body.get("negative")
        fps = body.get("fps")
        duration_s = body.get("duration_s")
        seed = body.get("seed")
        guidance = body.get("guidance")
        steps = body.get("steps")
        sampler = body.get("sampler")
        width = body.get("width")
        height = body.get("height")

    if not prompt:
        raise HTTPException(status_code=400, detail="Missing required field: prompt")
    if fps is None or duration_s is None:
        raise HTTPException(status_code=400, detail="Missing required fields: fps and duration_s")

    num_frames = int(round(int(fps) * float(duration_s)))

    # Résout et charge le template d'API Prompt
    tpl_path = get_template_path()
    log.info(f"[shim] Using template: {tpl_path}")
    api_prompt_template = _load_api_prompt_template(tpl_path)

    # Upload/lecture image
    async with httpx.AsyncClient(timeout=60) as client:
        if image is not None:
            img_bytes = await image.read()
            img_name = _safe_name(image.filename)
        elif image_url:
            r = await client.get(image_url)
            if r.status_code != 200:
                raise HTTPException(status_code=400, detail=f"Failed to fetch image_url: HTTP {r.status_code}")
            img_bytes = r.content
            clean = image_url.split("?")[0].split("#")[0]
            img_name = _safe_name(os.path.basename(clean) or "input.png")
        else:
            raise HTTPException(status_code=400, detail="Provide either image (file) or image_url")

        uploaded_name = await _comfy_upload_image(client, img_bytes, img_name)

        # ---------- valeurs par défaut typées (évite les '' qui cassent la validation) ----------
        seed_val = int(seed) if seed is not None else (int.from_bytes(os.urandom(4), "big") % (2**31))
        guidance_val = float(guidance) if guidance is not None else 4.5     # CFG
        steps_val = int(steps) if steps is not None else 20                  # steps
        sampler_val = (sampler or "dpmpp_2m").strip()                        # sampler existant par défaut

        # width/height : uniquement si fournis (ne pas écraser le template)
        wh_map: Dict[str, Any] = {}
        if width is not None:
            wh_map["__WIDTH__"] = int(width)
        if height is not None:
            wh_map["__HEIGHT__"] = int(height)

        mapping = {
            "__PROMPT__": prompt,
            "__NEGATIVE__": negative or "",
            "__FPS__": int(fps),
            "__DURATION_S__": float(duration_s),
            "__NUM_FRAMES__": num_frames,
            "__SEED__": seed_val,
            "__GUIDANCE__": guidance_val,
            "__STEPS__": steps_val,
            "__SAMPLER__": sampler_val,
            "__INPUT_IMAGE_FILENAME__": uploaded_name,
            **wh_map,  # n’ajoute WIDTH/HEIGHT que si définis
        }

        prompt_graph = _walk_replace(api_prompt_template, mapping)
        job_id = await _comfy_submit_prompt(client, prompt_graph)

    return JSONResponse({"job_id": job_id, "status": "queued"})


@app.get("/jobs/{job_id}")
async def get_job(job_id: str):
    async with httpx.AsyncClient(timeout=30) as client:
        history = await _comfy_history(client, job_id)
        if history:
            outs = _outputs_from_history(history)
            status = "completed" if outs else None
            if not status:
                q = await _comfy_queue(client)
                # basic status inference
                def _has(qkey):
                    items = q.get(qkey) or []
                    for it in items:
                        if isinstance(it, dict) and (it.get("id")==job_id or it.get("prompt_id")==job_id):
                            return True
                        if isinstance(it, (list, tuple)) and job_id in it:
                            return True
                    return False
                if _has("queue_running"): status = "running"
                elif _has("queue_pending"): status = "queued"
                else: status = "running"
            return JSONResponse({"job_id": job_id, "status": status, "outputs": outs})

        q = await _comfy_queue(client)
        # unknown but maybe queued
        for bucket in ("queue_running","queue_pending","running","queue"):
            for it in q.get(bucket, []):
                if isinstance(it, dict) and (it.get("id")==job_id or it.get("prompt_id")==job_id):
                    return JSONResponse({"job_id": job_id, "status": "running"})
                if isinstance(it, (list, tuple)) and job_id in it:
                    return JSONResponse({"job_id": job_id, "status": "running"})

    raise HTTPException(status_code=404, detail="job_id not found")
