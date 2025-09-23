# Conversation Change Tracker

## 2025-09-22
- Baked ComfyUI custom nodes into the Docker image with pinned revisions and optional GitHub token support.
- Hardened `start.sh` bootstrap: safe `pip_install_once`/`once`, optional Comfy/Sage sync flags, graceful node pin handling, and shim startup improvements.
- Added `shim/custom_nodes.lock` with audited pins, including ComfyUI-Manager.
- Introduced build-time bash shell usage for Docker RUN steps to support `set -euo pipefail`.
- Made SageAttention install tolerant of missing `nvcc`; it now skips build with a warning instead of crashing the pod.
- SageAttention clone now skips when the repo already exists, avoiding repeated fatal errors on subsequent boots.
- Runtime now only passes `--use-sage-attention` when the module loads successfully, removing noisy pip install prompts when CUDA tooling is absent.
