ComfyUI I2V Shim (WAN 2.2)

Overview

- Thin FastAPI layer that queues pre-built ComfyUI workflows for WAN 2.2 I2V jobs.
- Designed for RunPod: ComfyUI, the shim API, and optional JupyterLab start from the same container.
- Enforces API key auth and workflow path whitelisting so the pod can be exposed behind an ingress.

Authentication

- Every endpoint requires an API key. Set `SHIM_API_KEY` (and keep `SHIM_REQUIRE_API_KEY=1`) in the pod environment.
- Clients must send `X-API-Key: <value>` or append `?api_key=<value>`.
- `start.sh` refuses to boot the shim when `SHIM_REQUIRE_API_KEY=1` but the key is missing.

Endpoints

- GET `/health`
  - Returns `{"ok": true, "comfy": true|false, ...}` depending on ComfyUI availability.
- POST `/run` (multipart form)
  - `workflow` (file, optional JSON) **or** `workflow_path` (string under the allowed workflow roots).
  - `wait` (default `true`) → set to `false` to return immediately after queueing.
  - `wait_timeout_s` (float, optional) → overrides `SHIM_MAX_WAIT_SECONDS` when waiting for completion.
  - Additional fields are passed straight to the workflow JSON (see placeholders below).
  - Response when queued: `{ "job_id": "...", "status": "queued" }`.
  - When waiting succeeds: `{ job_id, status, outputs }` where `outputs` mirrors ComfyUI history.
  - If the timeout expires, a `504` is raised with `{"message": "...", "job_id": "..."}` so the client can keep polling.
- GET `/status/{job_id}`
  - Returns `{ job_id, status: queued|running|completed, outputs }`.
  - 404 if the job is unknown to both the queue and history.

Workflow Templates & Path Safety

- `SHIM_WORKFLOW_PATH` points to the default JSON used when neither `workflow` nor `workflow_path` is supplied.
- `SHIM_WORKFLOW_ROOT` (colon-separated list) and `SHIM_ADDITIONAL_WORKFLOW_ROOTS` define directories that the shim will read from. Any path outside these roots is rejected with `403`.
- Place string placeholders in the workflow to let the shim inject user parameters:
  - `__PROMPT__`, `__NEGATIVE__`
  - `__FPS__`, `__DURATION_S__`, `__SEED__`
  - `__GUIDANCE__`, `__STEPS__`, `__SAMPLER__`
  - `__WIDTH__`, `__HEIGHT__`
  - `__INPUT_IMAGE_FILENAME__`

Custom Node Pinning

- `start.sh` clones required custom nodes (KJNodes, GGUF, VideoHelperSuite, Frame Interpolation, Crystools, etc.).
- Provide exact revisions in `${CUSTOM_NODE_LOCK_FILE}` (defaults to `/opt/shim/custom_nodes.lock`) using the format `FolderName <commit-ish>` per line.
- Optional nodes are only cloned when pinned or when `ALLOW_UNPINNED_CUSTOM_NODES=1`.
- Running with `ALLOW_UNPINNED_CUSTOM_NODES=1` (the POC default) prints a warning; set it to `0` in production to fail fast if a pin is missing.

Environment Reference (partial)

- `SHIM_HOST`, `SHIM_PORT` – shim bind address (default `0.0.0.0:8080`).
- `SHIM_HTTP_TIMEOUT` – HTTP timeout to ComfyUI (seconds, default `120`).
- `SHIM_MAX_WAIT_SECONDS` – default blocking wait window for `/run` (seconds, default `600`).
- `SHIM_POLL_INTERVAL` – queue polling cadence (seconds, default `0.75`).
- `COMFY_API_URL` – override when ComfyUI is exposed elsewhere.
- `COMFY_UI_AUTOLOAD` – injects an extension that loads the default workflow on first visit (default `1`).
- `COMFY_UI_AUTOLOAD_ON_EVERY_VISIT` – when `1`, reload the workflow on every UI visit (default `1` now that the API relies on it).
- `JUPYTER_ENABLED` – set to `1` to start JupyterLab; when enabled the script creates a random token if none is provided.

Notes

- Status polling uses the REST queue/history endpoints; no WebSockets are needed.
- `/run` returns a 504 only when the wait budget is exhausted; clients should switch to `/status/{job_id}` afterwards.
- Always rotate `SHIM_API_KEY` when sharing pods between clients and prefer placing the shim behind your platform ingress.
