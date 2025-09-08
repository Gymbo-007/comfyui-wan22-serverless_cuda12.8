ComfyUI I2V Shim (WAN 2.2)

Overview

- Exposes a minimal REST API over ComfyUI to run I2V with a default workflow.
- Injects simple params (prompt, fps, duration, etc.) via string placeholders in a workflow template.
- Submits the job to ComfyUI and provides polling status and output URLs.

Endpoints

- POST `/i2v` (multipart or JSON)
  - image (file) or image_url (string URL)
  - prompt (string), negative (string, optional)
  - fps (int), duration_s (float)
  - seed (int, optional)
  - guidance, steps, sampler, width, height (optional)
  - Response: `{ "job_id": "...", "status": "queued" }`

- GET `/jobs/{job_id}`
  - Response: `{ job_id, status: queued|running|completed|failed, outputs: [ { url, filename, type, subfolder } ] }`

Workflow Template

The shim expects a ComfyUI workflow JSON to be available at `SHIM_WORKFLOW_PATH` (env). By default, it uses `DEFAULT_WORKFLOW` from the container if set, otherwise `/workspace/ComfyUI/user/default/workflows/Wan22_I2V_Native_3_stage.json`.

To allow parameter injection without coupling to specific node IDs, place the following placeholders where appropriate in your workflow JSON (as strings):

- `__PROMPT__`, `__NEGATIVE__`
- `__FPS__`, `__DURATION_S__`, `__SEED__`
- `__GUIDANCE__`, `__STEPS__`, `__SAMPLER__`
- `__WIDTH__`, `__HEIGHT__`
- `__INPUT_IMAGE_FILENAME__` (for LoadImage/Image input node)

Example: if your workflow has a LoadImage node, set its `image`/`inputs` field to `"__INPUT_IMAGE_FILENAME__"`. For CLIP text nodes, set the `text` field to `"__PROMPT__"` or `"__NEGATIVE__"`.

Environment

- `COMFY_HOST`, `COMFY_PORT` (ComfyUI bind; defaults set by container)
- `COMFY_API_URL` (defaults to `http://127.0.0.1:${COMFY_PORT}`)
- `SHIM_WORKFLOW_PATH` (defaults to `DEFAULT_WORKFLOW`)
- `SHIM_ENABLED`, `SHIM_HOST`, `SHIM_PORT` (default: 1, 0.0.0.0, 8080)

Notes

- The shim uses ComfyUI endpoints: `/upload/image`, `/prompt`, `/queue`, `/history/{job_id}`, and constructs output URLs via `/view`.
- No WebSocket is used; status is obtained via polling.
