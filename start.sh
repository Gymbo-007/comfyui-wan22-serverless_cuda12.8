#!/usr/bin/env bash
# RunPod-ready (root) — Jupyter config persistante (dark/light via env), terminal QoL, comfy boot timing,
# SageAttention, Crystools & Manager requis, optionnels via SKIP_OPTIONAL_NODES=0,
# workflow par défaut + auto-queue + autoload UI (installé dans le vrai web root)
set -uo pipefail

BOOT_T0=$(date +%s)

############################################
# Variables (surchargables via ENV)
############################################
WORKDIR="${WORKDIR:-/workspace}"
COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
VENV_DIR="${VENV_DIR:-/workspace/venv}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-/workspace/.cache/pip}"

COMFY_PORT="${COMFY_PORT:-8188}"
COMFY_HOST="${COMFY_HOST:-0.0.0.0}"

JUPYTER_PORT="${JUPYTER_PORT:-8888}"
JUPYTER_IP="${JUPYTER_IP:-0.0.0.0}"
JUPYTER_TOKEN="${JUPYTER_TOKEN:-}"
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"          # ex: kylee123
JUPYTER_PASSWORD_HASH="${JUPYTER_PASSWORD_HASH:-}"
JUPYTER_ALLOW_ORIGIN_PAT="${JUPYTER_ALLOW_ORIGIN_PAT:-.*runpod\.net}"
FORCE_JUPYTER_RESET="${FORCE_JUPYTER_RESET:-0}"
JUPYTER_THEME="${JUPYTER_THEME:-JupyterLab Dark}"

COMFY_SHA="${COMFY_SHA:-master}"
SKIP_OPTIONAL_NODES="${SKIP_OPTIONAL_NODES:-1}"

DEFAULT_WORKFLOW="${DEFAULT_WORKFLOW:-/workspace/ComfyUI/user/default/workflows/Wan22_I2V_Native_3_stage.json}"
COMFY_AUTO_QUEUE="${COMFY_AUTO_QUEUE:-0}"

COMFY_UI_AUTOLOAD="${COMFY_UI_AUTOLOAD:-1}"
COMFY_UI_AUTOLOAD_ON_EVERY_VISIT="${COMFY_UI_AUTOLOAD_ON_EVERY_VISIT:-0}"

CRYSTOOLS_REPO="${CRYSTOOLS_REPO:-https://github.com/crystian/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_1="${CRYSTOOLS_FALLBACK_1:-https://github.com/crystools/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_2="${CRYSTOOLS_FALLBACK_2:-https://github.com/crystoolsai/ComfyUI-Crystools.git}"
GH_TOKEN="${GH_TOKEN:-}"

COMFY_LOG="${WORKDIR}/logs/comfyui.log"
JUPYTER_LOG="${WORKDIR}/logs/jupyter.log"
METRICS_JSON="${WORKDIR}/logs/boot_metrics.json"
SHIM_LOG="${WORKDIR}/logs/shim.log"

# Shim
SHIM_ENABLED="${SHIM_ENABLED:-1}"
SHIM_HOST="${SHIM_HOST:-0.0.0.0}"
SHIM_PORT="${SHIM_PORT:-8080}"
SHIM_DIR="${SHIM_DIR:-/opt/shim}"
SHIM_WORKFLOW_PATH="${SHIM_WORKFLOW_PATH:-${DEFAULT_WORKFLOW}}"

export GIT_TERMINAL_PROMPT=0
export SHELL=/bin/bash

mkdir -p "$WORKDIR" "$PIP_CACHE_DIR" "$WORKDIR/logs" "$WORKDIR/models"
touch "$COMFY_LOG" "$JUPYTER_LOG" "$SHIM_LOG"
echo "[Init] WORKDIR=$WORKDIR"
echo "[Init] COMFY_DIR=$COMFY_DIR"
echo "[Init] VENV_DIR=$VENV_DIR"
echo "[Init] COMFY_SHA=$COMFY_SHA"
echo "[Init] SKIP_OPTIONAL_NODES=$SKIP_OPTIONAL_NODES"

export PIP_PREFER_BINARY=1
export PIP_NO_BUILD_ISOLATION=1

############################################
# 0) Terminal QoL
############################################
if ! grep -q ">>> KYLEE SHELL QoL >>>" ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc <<'BASHRC'
# >>> KYLEE SHELL QoL >>>
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
command -v fd  >/dev/null 2>&1 || alias fd='fdfind'
[ -f /etc/bash_completion ] && . /etc/bash_completion
PROMPT_COMMAND='echo -ne "\033]0;${PWD/#$HOME/~}\007"'
parse_git_branch() { git branch 2>/dev/null | sed -n "/^\*/s/^\* //p"; }
PS1='\[\e[0;36m\][\t]\[\e[0m\] \[\e[1;32m\]\u@\h\[\e[0m\]: \[\e[1;34m\]\w\[\e[0m\] \[\e[0;33m\]$(b=$(parse_git_branch); [ -n "$b" ] && echo "($b)")\[\e[0m\]\n$ '
# <<< KYLEE SHELL QoL <<<
BASHRC
fi

############################################
# 1) Venv
############################################
if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv --system-site-packages "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate" || true
python -V || true
pip install --upgrade pip wheel --cache-dir "$PIP_CACHE_DIR" || true

############################################
# 2) JupyterLab
############################################
JUPYTER_BIN="${JUPYTER_BIN:-$(command -v jupyter || true)}"
[ -z "$JUPYTER_BIN" ] && [ -x "$VENV_DIR/bin/jupyter" ] && JUPYTER_BIN="$VENV_DIR/bin/jupyter"
[ -z "$JUPYTER_BIN" ] && [ -x "/opt/conda/bin/jupyter" ] && JUPYTER_BIN="/opt/conda/bin/jupyter"

JCFG_DIR="/workspace/.jupyter"
mkdir -p "$JCFG_DIR/lab/user-settings/@jupyterlab/apputils-extension" "$JCFG_DIR/lab/user-settings/@jupyterlab/terminal-extension" "$JCFG_DIR/runtime"
[ -e ~/.jupyter ] || ln -s "$JCFG_DIR" ~/.jupyter
[ -L ~/.jupyter ] || { rm -rf ~/.jupyter; ln -s "$JCFG_DIR" ~/.jupyter; }

if [ -n "$JUPYTER_PASSWORD" ] && [ -z "$JUPYTER_PASSWORD_HASH" ]; then
  JUPYTER_PASSWORD_HASH="$(
    JUP_PLAIN="$JUPYTER_PASSWORD" python - <<'PY'
from jupyter_server.auth import passwd
import os
pwd = os.environ.get('JUP_PLAIN','')
print(passwd(pwd) if pwd else '', end='')
PY
  )"
fi
[ -f "$JCFG_DIR/jupyter_cookie_secret" ] || head -c 32 /dev/urandom > "$JCFG_DIR/jupyter_cookie_secret"

if [ "${FORCE_JUPYTER_RESET}" = "1" ] || [ ! -f "$JCFG_DIR/jupyter_server_config.py" ]; then
  cat > "$JCFG_DIR/jupyter_server_config.py" <<CFG
c = get_config()
c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = ${JUPYTER_PORT}
c.ServerApp.root_dir = "${WORKDIR}"
c.ServerApp.trust_xheaders = True
c.ServerApp.allow_remote_access = True
c.ServerApp.allow_origin_pat = r"${JUPYTER_ALLOW_ORIGIN_PAT}"
c.IdentityProvider.token = "${JUPYTER_TOKEN}"
c.PasswordIdentityProvider.hashed_password = u"${JUPYTER_PASSWORD_HASH}"
c.ServerApp.cookie_secret_file = "${JCFG_DIR}/jupyter_cookie_secret"
c.ServerApp.runtime_dir = "${JCFG_DIR}/runtime"
CFG
fi
cat > "$JCFG_DIR/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings" <<JSON
{ "theme": "${JUPYTER_THEME}" }
JSON
cat > "$JCFG_DIR/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings" <<'JSON'
{ "theme": "dark", "fontSize": 14, "cursorBlink": true, "scrollback": 10000 }
JSON

if [ -n "$JUPYTER_BIN" ]; then
  nohup "$JUPYTER_BIN" lab --no-browser --allow-root --config="${JCFG_DIR}/jupyter_server_config.py" > "${JUPYTER_LOG}" 2>&1 &
fi

############################################
# 3) ComfyUI
############################################
if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR" || true
fi
if [ -d "$COMFY_DIR/.git" ]; then
  cd "$COMFY_DIR"
  git fetch --all --tags || true
  git checkout "$COMFY_SHA" 2>/dev/null || git checkout origin/"$COMFY_SHA" || true
  [ -f requirements.txt ] && pip install -r requirements.txt --cache-dir "$PIP_CACHE_DIR" || true
fi

############################################
# 3.5) Shim deps
############################################
if [ -f "${SHIM_DIR}/requirements.txt" ]; then
  pip install -r "${SHIM_DIR}/requirements.txt" --cache-dir "$PIP_CACHE_DIR" || true
fi

############################################
# 4) SageAttention — wait CUDA + build
############################################
SAGE_SRC_DIR="${WORKDIR}/SageAttention"
if [ ! -d "${SAGE_SRC_DIR}/.git" ]; then
  git clone https://github.com/thu-ml/SageAttention.git "${SAGE_SRC_DIR}" || true
fi
if [ -d "${SAGE_SRC_DIR}" ]; then
  if python -c 'import importlib; importlib.import_module("sageattention")' >/dev/null 2>&1; then
    echo "[Sage] SageAttention already installed — skipping."
  else
    echo "[Sage] Waiting for CUDA (nvidia-smi)..."
    for i in $(seq 1 60); do
      if nvidia-smi >/dev/null 2>&1; then echo "[CUDA] nvidia-smi OK"; break; fi
      sleep 1
      [ "$i" -eq 60 ] && echo "[CUDA][WARN] nvidia-smi not ready; continue anyway."
    done

    echo "[Sage] Waiting for torch.cuda.is_available()..."
    for i in $(seq 1 60); do
      if "$VENV_DIR/bin/python" -c 'import torch, sys; sys.stdout.write(str(torch.cuda.is_available()))' 2>/dev/null | grep -q True; then
        echo "[CUDA] torch.cuda.is_available() == True"; break
      fi
      sleep 1
      [ "$i" -eq 60 ] && echo "[CUDA][WARN] torch.cuda still False; attempting build anyway."
    done

    echo "[Sage] Building/Installing SageAttention from source"
    export FORCE_CUDA=1
    export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-9.0}"  # RTX 5090 (Blackwell). Ajuste si besoin.
    export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32
    cd "${SAGE_SRC_DIR}" || true
    pip install -e . --no-build-isolation --cache-dir "$PIP_CACHE_DIR" || true
  fi
fi

############################################
# 5) Custom nodes (requis)
############################################
mkdir -p "$COMFY_DIR/custom_nodes"
cd "$COMFY_DIR/custom_nodes" 2>/dev/null || true

clone_node () {
  local repo="$1" folder="$2" required="$3" tries=0
  local auth=()
  [ -n "$GH_TOKEN" ] && auth=(-c http.extraheader="AUTHORIZATION: bearer ${GH_TOKEN}")
  if [ ! -d "$folder/.git" ] && [ ! -d "$folder" ]; then
    until git "${auth[@]}" clone --depth 1 "$repo" "$folder"; do
      tries=$((tries+1)); echo "[Node][WARN] clone failed ($tries) for $folder"
      [ "$tries" -ge 3 ] && { [ "$required" = "1" ] && echo "[Node][ERROR] required $folder failed"; break; }
      sleep 3
    done
  fi
  if [ -d "$folder" ] && [ -f "$folder/requirements.txt" ]; then
    pip install -r "$folder/requirements.txt" --cache-dir "$PIP_CACHE_DIR" || true
  fi
}

clone_node https://github.com/kijai/ComfyUI-KJNodes.git                    ComfyUI-KJNodes              1
clone_node https://github.com/city96/ComfyUI-GGUF.git                      ComfyUI-GGUF                1
clone_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git     ComfyUI-VideoHelperSuite    1
clone_node https://github.com/Fannovel16/comfyui-frame-interpolation.git   comfyui-frame-interpolation 1

clone_node "$CRYSTOOLS_REPO"  ComfyUI-Crystools 1
[ -d ComfyUI-Crystools/.git ] || clone_node "$CRYSTOOLS_FALLBACK_1" ComfyUI-Crystools 1
[ -d ComfyUI-Crystools/.git ] || clone_node "$CRYSTOOLS_FALLBACK_2" ComfyUI-Crystools 1
[ -f "ComfyUI-Crystools/requirements.txt" ] && pip install -r ComfyUI-Crystools/requirements.txt --cache-dir "$PIP_CACHE_DIR" || true

clone_node https://github.com/ltdrdata/ComfyUI-Manager.git                 ComfyUI-Manager             1

if [ "${SKIP_OPTIONAL_NODES}" = "0" ]; then
  clone_node https://github.com/cubiq/ComfyUI_Unload_Model.git            ComfyUI_Unload_Model        0
  clone_node https://github.com/rgthree/rgthree-comfy.git                 rgthree-comfy               0
  clone_node https://github.com/WASasquatch/was-node-suite-comfyui.git    was-node-suite-comfyui      0
  clone_node https://github.com/cubiq/ComfyUI_essentials.git              ComfyUI_essentials          0
  clone_node https://github.com/cubiq/ComfyUI-Easy-Use.git                ComfyUI-Easy-Use            0
fi

############################################
# 6) models symlink
############################################
cd "$COMFY_DIR" 2>/dev/null || true
mkdir -p /workspace/models
[ -d "$COMFY_DIR" ] && [ ! -L "$COMFY_DIR/models" ] && { rm -rf "$COMFY_DIR/models"; ln -s /workspace/models "$COMFY_DIR/models"; }

############################################
# 6.5) Workflow par défaut
############################################
WF_DST_DIR="${COMFY_DIR}/user/default/workflows"
mkdir -p "${WF_DST_DIR}"

COMFY_EXTRA_ARGS=()
if [ -f "${DEFAULT_WORKFLOW}" ]; then
  cp -f "${DEFAULT_WORKFLOW}" "${WF_DST_DIR}/_auto_default.json"
  [ "${COMFY_AUTO_QUEUE}" = "1" ] && COMFY_EXTRA_ARGS+=(--infinite-queue-at-startup "${DEFAULT_WORKFLOW}")
else
  echo "[Workflow][WARN] DEFAULT_WORKFLOW not found at: ${DEFAULT_WORKFLOW}"
fi

############################################
# 6.6) Web root + extension autoload
############################################
WEB_ROOT="$(python - <<'PY'
try:
    import importlib.resources as ir
    p = ir.files('comfyui_frontend_package') / 'static'
    print(str(p))
except Exception:
    print('')
PY
)"
[ -z "$WEB_ROOT" ] || [ ! -d "$WEB_ROOT" ] && WEB_ROOT="${COMFY_DIR}/web"
echo "[WebRoot] Using: $WEB_ROOT"

if [ "${COMFY_UI_AUTOLOAD}" = "1" ] && [ -f "${WF_DST_DIR}/_auto_default.json" ]; then
  EXT_DIR="${WEB_ROOT}/extensions/kylee-autoload"
  mkdir -p "${EXT_DIR}"
  cp -f "${WF_DST_DIR}/_auto_default.json" "${EXT_DIR}/default_workflow.json"
  cat > "${EXT_DIR}/main.js" <<'JS'
import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";
async function loadDefaultWorkflow({ everyVisit=false } = {}) {
  try {
    const FLAG = "kylee_autoload_done";
    if (!everyVisit && localStorage.getItem(FLAG) === "1") return;
    const candidates = [
      "/extensions/kylee-autoload/default_workflow.json",
      "/user/default/workflows/_auto_default.json",
      "/ComfyUI/user/default/workflows/_auto_default.json"
    ];
    let wf=null,lastErr=null;
    for (const url of candidates) {
      try { const r=await fetch(url,{cache:"no-store"});
        if (r.ok){ wf=await r.json(); console.log("[Kylee-Autoload] Loaded:", url); break; }
        lastErr=`HTTP ${r.status}`;
      } catch(e){ lastErr=e; }
    }
    if (!wf) { console.warn("[Kylee-Autoload] Could not fetch workflow:", lastErr); return; }
    await app.loadGraphData(wf);
    console.log("[Kylee-Autoload] Default workflow loaded.");
    if (!everyVisit) localStorage.setItem(FLAG,"1");
  } catch(e){ console.warn("[Kylee-Autoload] Failed:", e); }
}
app.registerExtension({ name:"kylee-autoload", async setup(){
  try { await api.ready; } catch {}
  const every = (window?.KYLEE_AUTOLOAD_EVERY_VISIT === true);
  setTimeout(()=>loadDefaultWorkflow({everyVisit: every}), 250);
}});
JS
  if [ "${COMFY_UI_AUTOLOAD_ON_EVERY_VISIT}" = "1" ]; then
    echo 'window.KYLEE_AUTOLOAD_EVERY_VISIT = true;' > "${EXT_DIR}/preload.js"
  else
    echo 'window.KYLEE_AUTOLOAD_EVERY_VISIT = false;' > "${EXT_DIR}/preload.js"
  fi
fi

############################################
# 7) Lancer ComfyUI + métriques ready
############################################
echo "[Run] Starting ComfyUI on ${COMFY_HOST}:${COMFY_PORT}"
start_comfy() {
  ( "$VENV_DIR/bin/python" "$COMFY_DIR/main.py" \
      --listen "$COMFY_HOST" \
      --port "$COMFY_PORT" \
      --disable-auto-launch \
      --use-sage-attention \
      "${COMFY_EXTRA_ARGS[@]}" \
      --log-stdout \
      2>&1 | tee -a "$COMFY_LOG" ) || true
  echo "[Run] ComfyUI exited with code $? — will retry in 5s"
}
( while true; do start_comfy; sleep 5; done ) &

(
  echo "[Probe] Waiting for ComfyUI on 127.0.0.1:${COMFY_PORT}"
  until curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null 2>&1; do sleep 1; done
  BOOT_T1=$(date +%s)
  BOOT_SECONDS=$(( BOOT_T1 - BOOT_T0 ))
  printf '{\n  "start_epoch": %s,\n  "ready_epoch": %s,\n  "comfy_ready_seconds": %s\n}\n' \
    "$BOOT_T0" "$BOOT_T1" "$BOOT_SECONDS" > "$METRICS_JSON"
  echo "[Metrics] ComfyUI ready in ${BOOT_SECONDS}s"
) &

############################################
# 8) Start Shim (optionnel)
############################################
start_shim() {
  echo "[Run] Starting Shim on ${SHIM_HOST}:${SHIM_PORT} (COMFY_API_URL=http://127.0.0.1:${COMFY_PORT})"
  (
    export COMFY_PORT COMFY_HOST
    export COMFY_API_URL="${COMFY_API_URL:-http://127.0.0.1:${COMFY_PORT}}"
    export SHIM_WORKFLOW_PATH
    cd "${SHIM_DIR}" || exit 0
    "${VENV_DIR}/bin/uvicorn" app:app --host "$SHIM_HOST" --port "$SHIM_PORT" 2>&1 | tee -a "$SHIM_LOG"
  ) || true
  echo "[Run] Shim exited with code $? — will retry in 5s"
}
[ "${SHIM_ENABLED}" = "1" ] && ( while true; do start_shim; sleep 5; done ) &

tail -F "$COMFY_LOG" "$JUPYTER_LOG" "$SHIM_LOG"
