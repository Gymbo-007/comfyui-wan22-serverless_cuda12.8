#!/usr/bin/env bash
# Fast boot for ComfyUI + Shim on RunPod
set -Eeuo pipefail

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

JUPYTER_ENABLED="${JUPYTER_ENABLED:-0}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
JUPYTER_IP="${JUPYTER_IP:-0.0.0.0}"
JUPYTER_TOKEN="${JUPYTER_TOKEN:-}"
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"
JUPYTER_PASSWORD_HASH="${JUPYTER_PASSWORD_HASH:-}"
JUPYTER_ALLOW_ORIGIN_PAT="${JUPYTER_ALLOW_ORIGIN_PAT:-.*runpod\.net}"
FORCE_JUPYTER_RESET="${FORCE_JUPYTER_RESET:-0}"
JUPYTER_THEME="${JUPYTER_THEME:-JupyterLab Dark}"

COMFY_SHA="${COMFY_SHA:-master}"
COMFY_SYNC_ON_BOOT="${COMFY_SYNC_ON_BOOT:-0}"

SKIP_OPTIONAL_NODES="${SKIP_OPTIONAL_NODES:-1}"
SAGE_ENABLE="${SAGE_ENABLE:-0}"   # 0 par défaut pour un boot rapide

DEFAULT_WORKFLOW="${DEFAULT_WORKFLOW:-/opt/workflows/wan2.2-runpod.sim.json}"
COMFY_AUTO_QUEUE="${COMFY_AUTO_QUEUE:-0}"

COMFY_UI_AUTOLOAD="${COMFY_UI_AUTOLOAD:-1}"
COMFY_UI_AUTOLOAD_ON_EVERY_VISIT="${COMFY_UI_AUTOLOAD_ON_EVERY_VISIT:-1}"

CRYSTOOLS_REPO="${CRYSTOOLS_REPO:-https://github.com/crystian/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_1="${CRYSTOOLS_FALLBACK_1:-https://github.com/crystools/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_2="${CRYSTOOLS_FALLBACK_2:-https://github.com/crystoolsai/ComfyUI-Crystools.git}"
GH_TOKEN="${GH_TOKEN:-}"

# Manager désactivé par défaut (évite le crawl lent au boot)
ENABLE_MANAGER="${ENABLE_MANAGER:-0}"

# Shim
SHIM_ENABLED="${SHIM_ENABLED:-1}"
SHIM_HOST="${SHIM_HOST:-0.0.0.0}"
SHIM_PORT="${SHIM_PORT:-8080}"
SHIM_DIR="${SHIM_DIR:-/opt/shim}"
SHIM_WORKFLOW_PATH="${SHIM_WORKFLOW_PATH:-/opt/workflows/wan2.2-runpod.json}"
SHIM_WORKERS="${SHIM_WORKERS:-1}"
SHIM_LOG_LEVEL="${SHIM_LOG_LEVEL:-info}"
SHIM_RELOAD="${SHIM_RELOAD:-0}"
SHIM_REQUIRE_API_KEY="${SHIM_REQUIRE_API_KEY:-1}"
SHIM_API_KEY="${SHIM_API_KEY:-}"

OPENCV_SYSTEM_DEPS="${OPENCV_SYSTEM_DEPS:-1}"

CUSTOM_NODE_LOCK_FILE="${CUSTOM_NODE_LOCK_FILE:-${SHIM_DIR}/custom_nodes.lock}"
ALLOW_UNPINNED_CUSTOM_NODES="${ALLOW_UNPINNED_CUSTOM_NODES:-0}"
CUSTOM_NODE_SYNC_ON_BOOT="${CUSTOM_NODE_SYNC_ON_BOOT:-0}"

# Logs
COMFY_LOG="${WORKDIR}/logs/comfyui.log"
JUPYTER_LOG="${WORKDIR}/logs/jupyter.log"
METRICS_JSON="${WORKDIR}/logs/boot_metrics.json"
SHIM_LOG="${WORKDIR}/logs/shim.log"

export GIT_TERMINAL_PROMPT=0
export SHELL=/bin/bash
export PIP_PREFER_BINARY=1
export PIP_NO_BUILD_ISOLATION=1

mkdir -p "$WORKDIR" "$PIP_CACHE_DIR" "$WORKDIR/logs" "$WORKDIR/models"

if [ -n "$GH_TOKEN" ]; then
  git config --global url."https://${GH_TOKEN}@github.com/".insteadOf "https://github.com/"
  git config --global credential.helper ""
fi

echo "[Init] WORKDIR=$WORKDIR"
echo "[Init] COMFY_DIR=$COMFY_DIR"
echo "[Init] VENV_DIR=$VENV_DIR"
echo "[Init] COMFY_SHA=$COMFY_SHA"
echo "[Init] SKIP_OPTIONAL_NODES=$SKIP_OPTIONAL_NODES SAGE_ENABLE=$SAGE_ENABLE ENABLE_MANAGER=$ENABLE_MANAGER"
echo "[Init] JUPYTER_ENABLED=$JUPYTER_ENABLED PORT=$JUPYTER_PORT"

############################################
# Helpers install-once / stamps
############################################
stamp_dir="${WORKDIR}/.stamps"; mkdir -p "$stamp_dir"

hash_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

pip_install_once() {
  local req="$1" name="${2:-}"
  if [ -z "$name" ]; then
    name="$(basename "${req}")"
  fi
  local stamp="${stamp_dir}/${name}.stamp"
  local cur=""; [ -f "$req" ] && cur="$(hash_of "$req")"
  if [ -s "$stamp" ] && [ "x$(cat "$stamp")" = "x$cur" ]; then
    echo "[PIP] ${name} already satisfied."
  else
    echo "[PIP] Installing ${name}…"
    if \
      "${VENV_DIR}/bin/pip" install --no-input --upgrade -r "$req" --cache-dir "$PIP_CACHE_DIR"; then
      echo -n "$cur" > "$stamp"
    else
      echo "[PIP][WARN] Installation failed for ${name}; will retry next boot." >&2
    fi
  fi
}

ensure_jupyter_deps() {
  local stamp="${stamp_dir}/jupyter-deps.done"
  if [ -s "$stamp" ]; then
    echo "[Jupyter] Dependencies already satisfied."
    return 0
  fi
  echo "[Jupyter] Installing core dependencies…"
  if "${VENV_DIR}/bin/pip" install --no-input --cache-dir "$PIP_CACHE_DIR" jupyterlab jupyter_server; then
    : > "$stamp"
    echo "[Jupyter] Dependencies installed."
    return 0
  fi
  echo "[Jupyter][WARN] Failed installing dependencies; will retry next boot." >&2
  return 1
}

once() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "[ONCE][ERROR] Missing stamp name" >&2
    return 1
  fi
  shift
  local stamp="${stamp_dir}/${name}.done"
  if [ -s "$stamp" ]; then
    echo "[ONCE] ${name} already done."
  else
    echo "[ONCE] ${name} running…"
    if ( "$@" ); then
      : > "$stamp"
    else
      echo "[ONCE][WARN] ${name} failed (will retry next boot)" >&2
    fi
  fi
}

############################################
# 0) Terminal QoL (idempotent)
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
"${VENV_DIR}/bin/pip" install --upgrade pip wheel --cache-dir "$PIP_CACHE_DIR" || true

############################################
# 2) JupyterLab (idempotent, non-bloquant)
############################################
if [ "$JUPYTER_ENABLED" = "1" ]; then
  if ! ensure_jupyter_deps; then
    echo "[Jupyter][WARN] Dependencies missing; skipping startup."
  else
    declare -a jupyter_subcmd=("lab")
    JUPYTER_BIN="${JUPYTER_BIN:-$(command -v jupyter || true)}"
    [ -z "$JUPYTER_BIN" ] && [ -x "$VENV_DIR/bin/jupyter" ] && JUPYTER_BIN="$VENV_DIR/bin/jupyter"
    [ -z "$JUPYTER_BIN" ] && [ -x "/opt/conda/bin/jupyter" ] && JUPYTER_BIN="/opt/conda/bin/jupyter"
    if [ -z "$JUPYTER_BIN" ] && [ -x "$VENV_DIR/bin/jupyter-lab" ]; then
      JUPYTER_BIN="$VENV_DIR/bin/jupyter-lab"
      jupyter_subcmd=()
    fi
    if [ -z "$JUPYTER_BIN" ] && [ -x "/opt/conda/bin/jupyter-lab" ]; then
      JUPYTER_BIN="/opt/conda/bin/jupyter-lab"
      jupyter_subcmd=()
    fi
    if [ -z "$JUPYTER_BIN" ] && [ -x "$VENV_DIR/bin/python" ]; then
      JUPYTER_BIN="$VENV_DIR/bin/python"
      jupyter_subcmd=(-m jupyterlab)
    fi
    if [ -z "$JUPYTER_BIN" ] && command -v python3 >/dev/null 2>&1; then
      JUPYTER_BIN="$(command -v python3)"
      jupyter_subcmd=(-m jupyterlab)
    fi

    if [ -z "$JUPYTER_TOKEN" ] && [ -z "$JUPYTER_PASSWORD" ] && [ -z "$JUPYTER_PASSWORD_HASH" ]; then
      JUPYTER_TOKEN="$(python - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
      )"
      export JUPYTER_TOKEN
      mkdir -p "${WORKDIR}/logs"
      chmod 700 "${WORKDIR}/logs"
      printf '%s' "$JUPYTER_TOKEN" > "${WORKDIR}/logs/jupyter_token.txt"
      chmod 600 "${WORKDIR}/logs/jupyter_token.txt"
      echo "[Jupyter] Generated one-time token; stored in ${WORKDIR}/logs/jupyter_token.txt"
    fi
  
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
  
    jcfg_file="$JCFG_DIR/jupyter_server_config.py"
    if [ "${FORCE_JUPYTER_RESET}" = "1" ] || [ ! -f "$jcfg_file" ] || grep -q '^  c = get_config()' "$jcfg_file" 2>/dev/null; then
      cat > "$jcfg_file" <<CFG
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
    echo "{ \"theme\": \"${JUPYTER_THEME}\" }" > "$JCFG_DIR/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings"
    cat > "$JCFG_DIR/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings" <<'JSON'
  { "theme": "dark", "fontSize": 14, "cursorBlink": true, "scrollback": 10000 }
JSON
  
    if [ -n "$JUPYTER_BIN" ]; then
      declare -a jupyter_cmd=("$JUPYTER_BIN")
      if [ ${#jupyter_subcmd[@]} -gt 0 ]; then
        jupyter_cmd+=("${jupyter_subcmd[@]}")
      fi
      jupyter_cmd+=(--no-browser --allow-root --config="${JCFG_DIR}/jupyter_server_config.py")
      echo "[Jupyter] Launching: ${jupyter_cmd[*]}"
      nohup "${jupyter_cmd[@]}" > "${JUPYTER_LOG}" 2>&1 &
    else
      echo "[Jupyter][WARN] JupyterLab not found; skipping startup."
    fi
  fi
else
  echo "[Jupyter] Disabled (set JUPYTER_ENABLED=1 to enable)."
fi

############################################
# 3) ComfyUI (ultra-rapide)
############################################
if [ ! -d "$COMFY_DIR/.git" ]; then
  echo "[Comfy] Cloning ComfyUI (${COMFY_SHA}) into ${COMFY_DIR}"
  git clone --depth 1 --branch "${COMFY_SHA}" https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
  git -C "$COMFY_DIR" remote set-url origin https://github.com/comfyanonymous/ComfyUI.git >/dev/null 2>&1 || true
elif [ "${COMFY_SYNC_ON_BOOT}" = "1" ]; then
  echo "[Comfy] Syncing ComfyUI to ${COMFY_SHA} (COMFY_SYNC_ON_BOOT=1)"
  ( cd "$COMFY_DIR" && git fetch origin "${COMFY_SHA}" --depth 1 && git checkout -qf FETCH_HEAD )
  git -C "$COMFY_DIR" remote set-url origin https://github.com/comfyanonymous/ComfyUI.git >/dev/null 2>&1 || true
else
  echo "[Comfy] Using baked ComfyUI repo; set COMFY_SYNC_ON_BOOT=1 to refresh."
fi
if [ -f "$COMFY_DIR/requirements.txt" ]; then
  pip_install_once "$COMFY_DIR/requirements.txt" "comfyui-reqs"
fi

############################################
# 3.5) Shim deps (si requirements présents)
############################################
if [ -f "${SHIM_DIR}/requirements.txt" ]; then
  pip_install_once "${SHIM_DIR}/requirements.txt" "shim-reqs"
fi

if [ "${OPENCV_SYSTEM_DEPS}" = "1" ]; then
  once "apt-opencv-deps-v2" bash -lc "DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libgl1-mesa-glx libglib2.0-0 libsm6 libxrender1 libxext6"
fi

############################################
# 4) SageAttention — optionnel + stamp
############################################
SAGE_SRC_DIR="${WORKDIR}/SageAttention"
USE_SAGE_ATTENTION=0
if [ "${SAGE_ENABLE}" = "1" ]; then
  once "apt-python-dev" bash -lc '
    if dpkg -s python3-dev >/dev/null 2>&1; then
      exit 0
    fi
    echo "[Sage][APT] Installing python3-dev for CUDA extension build…"
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-dev
  '
  if [ -d "${SAGE_SRC_DIR}/.git" ]; then
    echo "[Sage] Repository already present at ${SAGE_SRC_DIR}"
  else
    once "sage-clone" bash -lc "git clone https://github.com/thu-ml/SageAttention.git '${SAGE_SRC_DIR}'"
  fi
  if ! python -c 'import importlib; importlib.import_module("sageattention")' >/dev/null 2>&1; then
    NVCC_BIN="${CUDA_HOME:-/usr/local/cuda}/bin/nvcc"
    if [ ! -x "$NVCC_BIN" ]; then
      echo "[Sage][WARN] nvcc not found at ${NVCC_BIN}; skipping SageAttention build (set SAGE_ENABLE=0 to silence)." >&2
    else
      echo "[Sage] Quick CUDA checks…"
      ( nvidia-smi >/dev/null 2>&1 && echo "[CUDA] nvidia-smi OK" ) || echo "[CUDA][WARN] nvidia-smi not ready"
      ( python - <<'PY' || true
import torch, sys
sys.stdout.write("CUDA="+str(torch.cuda.is_available()))
PY
      ) || true
      echo "[Sage] Building once…"
      export FORCE_CUDA=1
      export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-9.0}"
      once "sage-build" bash -lc "cd '${SAGE_SRC_DIR}' && pip install -e . --no-build-isolation --cache-dir '$PIP_CACHE_DIR'"
    fi
  fi
  if python -c 'import importlib; importlib.import_module("sageattention")' >/dev/null 2>&1; then
    echo "[Sage] Module available; enabling --use-sage-attention"
    USE_SAGE_ATTENTION=1
  else
    echo "[Sage][WARN] Module still unavailable; continuing without SageAttention." >&2
  fi
else
  echo "[Sage] Disabled (SAGE_ENABLE=0)."
fi

############################################
# 5) Custom nodes (clones sécurisés)
############################################
mkdir -p "$COMFY_DIR/custom_nodes"
cd "$COMFY_DIR/custom_nodes" 2>/dev/null || true

if [ "$ALLOW_UNPINNED_CUSTOM_NODES" = "1" ]; then
  echo "[Node][WARN] Custom nodes will run without pins (ALLOW_UNPINNED_CUSTOM_NODES=1)." >&2
  echo "[Node][WARN] Provide ${CUSTOM_NODE_LOCK_FILE} or CUSTOM_NODE_*_REF to lock versions." >&2
fi

if [ ! -f "$CUSTOM_NODE_LOCK_FILE" ] && [ -f "${CUSTOM_NODE_LOCK_FILE}.example" ]; then
  echo "[Node][INFO] Copy ${CUSTOM_NODE_LOCK_FILE}.example to ${CUSTOM_NODE_LOCK_FILE} and set real revisions."
fi

upper_key() {
  echo "$1" | tr '[:lower:]' '[:upper:]' | tr '/.-' '___'
}

lookup_node_pin() {
  local folder="$1" env_key pin line name ref
  env_key="CUSTOM_NODE_$(upper_key "$folder")_REF"
  pin="${!env_key:-}"
  if [ -n "$pin" ]; then
    echo "$pin"
    return 0
  fi
  if [ -f "$CUSTOM_NODE_LOCK_FILE" ]; then
    while read -r name ref _; do
      case "$name" in
        ''|'#'* ) continue ;;
      esac
      if [ "$name" = "$folder" ]; then
        echo "$ref"
        return 0
      fi
    done < "$CUSTOM_NODE_LOCK_FILE"
  fi
  echo ""
}

clone_node() {
  local repo="$1" folder="$2" pin
  pin="$(lookup_node_pin "$folder")"
  local have_repo=0
  if [ -d "$folder/.git" ]; then
    have_repo=1
    git -C "$folder" remote set-url origin "$repo" >/dev/null 2>&1 || true
    local current
    current="$(cd "$folder" && git rev-parse HEAD 2>/dev/null || echo '')"
    if [ -n "$pin" ]; then
      if [ "$current" = "$pin" ]; then
        ( cd "$folder" && printf '%s' "$current" > .pinned-ref 2>/dev/null || true )
        echo "[Node] ${folder} already pinned to ${current}"
        return 0
      fi
      if [ "$CUSTOM_NODE_SYNC_ON_BOOT" = "1" ]; then
        (
          set -e
          cd "$folder"
          git fetch --depth 1 origin "$pin"
          git checkout -qf FETCH_HEAD
          git rev-parse HEAD > .pinned-ref
        )
        local synced
        synced="$(cd "$folder" && git rev-parse HEAD 2>/dev/null || echo unknown)"
        echo "[Node] ${folder} synced to ${synced}"
        return 0
      fi
      echo "[Node][WARN] ${folder} present at ${current:-unknown} but pin ${pin} requested; leaving as-is." >&2
      return 0
    fi
    if [ "$ALLOW_UNPINNED_CUSTOM_NODES" = "1" ]; then
      echo "[Node][WARN] ${folder} running unpinned (ALLOW_UNPINNED_CUSTOM_NODES=1)." >&2
      return 0
    fi
    echo "[Node][ERROR] Missing pin for ${folder}; define it in ${CUSTOM_NODE_LOCK_FILE} or set CUSTOM_NODE_$(upper_key "$folder")_REF." >&2
    return 1
  fi

  if [ "$have_repo" -eq 0 ]; then
    if [ -z "$pin" ] && [ "$ALLOW_UNPINNED_CUSTOM_NODES" != "1" ]; then
      echo "[Node][ERROR] Missing pin for ${folder}; define it in ${CUSTOM_NODE_LOCK_FILE} or set CUSTOM_NODE_$(upper_key "$folder")_REF." >&2
      return 1
    fi
    echo "[Node] Cloning ${folder} from ${repo}…"
    if ! git clone --filter=blob:none --origin origin "$repo" "$folder"; then
      echo "[Node][ERROR] Clone failed for ${folder}." >&2
      return 1
    fi
    have_repo=1
  fi

  if [ ! -d "$folder/.git" ]; then
    echo "[Node][ERROR] Repository ${folder} unavailable after clone." >&2
    return 1
  fi

  git -C "$folder" remote set-url origin "$repo" >/dev/null 2>&1 || true
  if [ -n "$pin" ]; then
    (
      set -e
      cd "$folder"
      git fetch --depth 1 origin "$pin"
      git checkout -qf FETCH_HEAD
      git rev-parse HEAD > .pinned-ref
    )
    local pinned
    pinned="$(cd "$folder" && git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "[Node] ${folder} pinned to ${pinned}"
  elif [ "$ALLOW_UNPINNED_CUSTOM_NODES" = "1" ]; then
    echo "[Node][WARN] ${folder} running unpinned (ALLOW_UNPINNED_CUSTOM_NODES=1)." >&2
  fi
}

clone_node_with_fallback() {
  local folder="$1"
  shift
  local repo
  for repo in "$@"; do
    [ -z "$repo" ] && continue
    if clone_node "$repo" "$folder"; then
      return 0
    fi
    echo "[Node][WARN] Failed cloning ${folder} from ${repo}; trying next fallback…" >&2
    rm -rf "$folder"
  done
  return 1
}

require_node_pin() {
  local folder="$1"
  if [ -z "$(lookup_node_pin "$folder")" ] && [ "$ALLOW_UNPINNED_CUSTOM_NODES" != "1" ] && [ ! -d "$folder/.git" ]; then
    echo "[Node][ERROR] Missing pin for mandatory node ${folder}." >&2
    return 1
  fi
  return 0
}

maybe_clone_optional() {
  local repo="$1" folder="$2"
  if [ -d "$folder/.git" ] || [ -n "$(lookup_node_pin "$folder")" ] || [ "$ALLOW_UNPINNED_CUSTOM_NODES" = "1" ]; then
    clone_node "$repo" "$folder"
  else
    echo "[Node][INFO] Skipping optional node ${folder} (no pin provided)."
  fi
}

require_node_pin ComfyUI-KJNodes
require_node_pin ComfyUI-GGUF
require_node_pin ComfyUI-VideoHelperSuite
require_node_pin comfyui-frame-interpolation

clone_node https://github.com/kijai/ComfyUI-KJNodes.git                    ComfyUI-KJNodes
clone_node https://github.com/city96/ComfyUI-GGUF.git                      ComfyUI-GGUF
clone_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git     ComfyUI-VideoHelperSuite
clone_node https://github.com/Fannovel16/comfyui-frame-interpolation.git   comfyui-frame-interpolation

clone_node_with_fallback ComfyUI-Crystools "${CRYSTOOLS_REPO}" "${CRYSTOOLS_FALLBACK_1}" "${CRYSTOOLS_FALLBACK_2}"

if [ "${ENABLE_MANAGER}" = "1" ]; then
  clone_node https://github.com/ltdrdata/ComfyUI-Manager.git               ComfyUI-Manager
  export COMFYUI_MANAGER_DISABLE_STARTUP_TASKS=1
  export COMFYUI_MANAGER_SKIP_FETCH=1
fi

if [ "${SKIP_OPTIONAL_NODES}" = "0" ]; then
  maybe_clone_optional https://github.com/cubiq/ComfyUI_Unload_Model.git            ComfyUI_Unload_Model
  maybe_clone_optional https://github.com/rgthree/rgthree-comfy.git                 rgthree-comfy
  maybe_clone_optional https://github.com/WASasquatch/was-node-suite-comfyui.git    was-node-suite-comfyui
  maybe_clone_optional https://github.com/cubiq/ComfyUI_essentials.git              ComfyUI_essentials
  maybe_clone_optional https://github.com/cubiq/ComfyUI-Easy-Use.git                ComfyUI-Easy-Use
fi

# pip install (requirements si présents, avec stamp par dossier)
for d in */ ; do
  [ -f "${d}requirements.txt" ] || continue
  pip_install_once "${d}requirements.txt" "node-$(basename "$d")"
done

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

WF_HASH=""
COMFY_EXTRA_ARGS=()
if [ -f "${DEFAULT_WORKFLOW}" ]; then
  cp -f "${DEFAULT_WORKFLOW}" "${WF_DST_DIR}/_auto_default.json"
  WF_HASH="$(hash_of "${WF_DST_DIR}/_auto_default.json")"
  echo "[Workflow] Installed default workflow → ${WF_DST_DIR}/_auto_default.json (sha=${WF_HASH:-unknown})"
  # Backward compatibility: keep legacy shim path populated if env still points there
  LEGACY_SHIM_DIR="/workspace/shim/templates"
  LEGACY_SHIM_PATH="${LEGACY_SHIM_DIR}/wan-2.2_shimv1.1-for-shim.json"
  mkdir -p "${LEGACY_SHIM_DIR}"
  if [ -f "${SHIM_WORKFLOW_PATH}" ]; then
    cp -f "${SHIM_WORKFLOW_PATH}" "${LEGACY_SHIM_PATH}"
    echo "[Workflow] Legacy shim copy refreshed at ${LEGACY_SHIM_PATH}"
  fi
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
  AUTOLOAD_FLAG="kylee_autoload_done"
  if [ -n "${WF_HASH}" ]; then
    AUTOLOAD_FLAG="kylee_autoload_done_${WF_HASH}"
  fi
  EVERY_VISIT="false"
  if [ "${COMFY_UI_AUTOLOAD_ON_EVERY_VISIT}" = "1" ]; then
    EVERY_VISIT="true"
  fi
  echo "[Workflow] Autoload extension ready at ${EXT_DIR} (flag=${AUTOLOAD_FLAG} every_visit=${EVERY_VISIT})"
  cat > "${EXT_DIR}/main.js" <<JS
import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

async function loadDefaultWorkflow({ everyVisit = false } = {}) {
  const FLAG = "${AUTOLOAD_FLAG}";
  if (!everyVisit && window.localStorage.getItem(FLAG) === "1") {
    return;
  }

  const candidates = [
    "/extensions/kylee-autoload/default_workflow.json",
    "/user/default/workflows/_auto_default.json",
    "/ComfyUI/user/default/workflows/_auto_default.json",
  ];

  let workflow = null;
  let lastErr = null;
  for (const url of candidates) {
    try {
      const res = await fetch(url, { cache: "no-store" });
      if (res.ok) {
        workflow = await res.json();
        console.log("[Kylee-Autoload] Loaded:", url);
        break;
      }
      lastErr = "HTTP " + res.status;
    } catch (err) {
      lastErr = err;
    }
  }
  if (!workflow) {
    console.warn("[Kylee-Autoload] Could not fetch workflow:", lastErr);
    return;
  }

  try {
    await app.loadGraphData(workflow);
    console.log("[Kylee-Autoload] Default workflow loaded. everyVisit=" + everyVisit);
    if (everyVisit) {
      window.localStorage.removeItem(FLAG);
    } else {
      window.localStorage.setItem(FLAG, "1");
    }
  } catch (err) {
    console.warn("[Kylee-Autoload] Failed to load workflow:", err);
  }
}

app.registerExtension({
  name: "kylee-autoload",
  async setup() {
    try {
      await api.ready;
    } catch (err) {
      console.warn("[Kylee-Autoload] api.ready failed:", err);
    }
    const every = window?.KYLEE_AUTOLOAD_EVERY_VISIT === true;
    if (every) {
      window.localStorage.removeItem("${AUTOLOAD_FLAG}");
    }
    setTimeout(() => loadDefaultWorkflow({ everyVisit: every }), 250);
  },
});
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
  local cmd=(
    "$VENV_DIR/bin/python" "$COMFY_DIR/main.py"
    --listen "$COMFY_HOST"
    --port "$COMFY_PORT"
    --disable-auto-launch
  )
  if [ "${USE_SAGE_ATTENTION}" = "1" ]; then
    cmd+=(--use-sage-attention)
  fi
  cmd+=("${COMFY_EXTRA_ARGS[@]}")
  cmd+=(--log-stdout)
  ( "${cmd[@]}" 2>&1 | tee -a "$COMFY_LOG" ) || true
  echo "[Run] ComfyUI exited with code $? — will retry in 5s"
}
( while true; do start_comfy; sleep 5; done ) &

(
  command -v curl >/dev/null 2>&1 || (apt-get update && apt-get install -y curl >/dev/null 2>&1 || true)
  echo "[Probe] Waiting for ComfyUI on 127.0.0.1:${COMFY_PORT}"
  until curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null 2>&1; do sleep 1; done
  BOOT_T1=$(date +%s)
  BOOT_SECONDS=$(( BOOT_T1 - BOOT_T0 ))
  printf '{\n  "start_epoch": %s,\n  "ready_epoch": %s,\n  "comfy_ready_seconds": %s\n}\n' \
    "$BOOT_T0" "$BOOT_T1" "$BOOT_SECONDS" > "$METRICS_JSON"
  echo "[Metrics] ComfyUI ready in ${BOOT_SECONDS}s"
) &

############################################
# 8) Start Shim (robuste)
############################################
ensure_shim_deps() {
  "$VENV_DIR/bin/python" - <<'PY' 2>/dev/null || "$VENV_DIR/bin/pip" install --no-input --cache-dir "$PIP_CACHE_DIR" uvicorn fastapi httpx
import uvicorn, fastapi, httpx
print("OK")
PY
  if [ -f "${SHIM_DIR}/requirements.txt" ]; then
    "$VENV_DIR/bin/pip" install --no-input --cache-dir "$PIP_CACHE_DIR" -r "${SHIM_DIR}/requirements.txt" || true
  fi
}

wait_http() {
  local url="$1" tries="${2:-120}" delay="${3:-1}"
  command -v curl >/dev/null 2>&1 || (apt-get update && apt-get install -y curl >/dev/null 2>&1 || true)
  for i in $(seq 1 "$tries"); do
    if curl -fsS "$url" >/dev/null 2>&1; then return 0; fi
    sleep "$delay"
  done
  return 1
}

start_shim() {
  if [ "${SHIM_REQUIRE_API_KEY}" = "1" ] && [ -z "${SHIM_API_KEY}" ]; then
    echo "[Shim][ERROR] SHIM_API_KEY is required (set SHIM_REQUIRE_API_KEY=0 to bypass)."
    return 1
  fi
  echo "[Run] Starting Shim on ${SHIM_HOST}:${SHIM_PORT} (COMFY_API_URL=http://127.0.0.1:${COMFY_PORT})"
  ensure_shim_deps
  export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}${SHIM_DIR}"
  export COMFY_PORT COMFY_HOST
  export COMFY_API_URL="${COMFY_API_URL:-http://127.0.0.1:${COMFY_PORT}}"
  export SHIM_WORKFLOW_PATH
  export SHIM_API_KEY
  export SHIM_REQUIRE_API_KEY
  export SHIM_WORKFLOW_ROOT="${SHIM_WORKFLOW_ROOT:-$(dirname "${SHIM_WORKFLOW_PATH}")}"

  local comfy_url="http://127.0.0.1:${COMFY_PORT}/"
  if ! wait_http "$comfy_url" 180 1; then
    echo "[Shim][WARN] ComfyUI ne répond pas encore sur ${comfy_url}. On démarre quand même."
  fi

  mkdir -p "$(dirname "$SHIM_LOG")"
  (
    flock -n 9 || { echo "[Shim][WARN] déjà en cours, skip."; exit 0; }
    cd "${SHIM_DIR}" || { echo "[Shim][ERROR] SHIM_DIR introuvable: ${SHIM_DIR}"; exit 0; }
    "$VENV_DIR"/bin/python - <<'PY' || { echo "[Shim][ERROR] Impossible d'importer app:app"; exit 0; }
import importlib
m = importlib.import_module("app")
getattr(m, "app")
print("OK: app:app")
PY

    echo "[Shim] uvicorn app:app --host ${SHIM_HOST} --port ${SHIM_PORT} --workers ${SHIM_WORKERS} --log-level ${SHIM_LOG_LEVEL}"
    if [ "${SHIM_RELOAD}" = "1" ]; then
      "${VENV_DIR}/bin/uvicorn" app:app --host "${SHIM_HOST}" --port "${SHIM_PORT}" --log-level "${SHIM_LOG_LEVEL}" --reload 2>&1 | tee -a "${SHIM_LOG}"
    else
      "${VENV_DIR}/bin/uvicorn" app:app --host "${SHIM_HOST}" --port "${SHIM_PORT}" --workers "${SHIM_WORKERS}" --log-level "${SHIM_LOG_LEVEL}" 2>&1 | tee -a "${SHIM_LOG}"
    fi
  ) 9>/tmp/shim.lock

  local rc=$?
  echo "[Run] Shim exited with code ${rc} — retry in 5s"
}

trap 'echo "[Trap] SIGTERM"; pkill -TERM -P $$ || true; exit 0' TERM INT

if [ "${SHIM_ENABLED}" = "1" ]; then
  if [ "${SHIM_REQUIRE_API_KEY}" = "1" ] && [ -z "${SHIM_API_KEY}" ]; then
    echo "[Shim][ERROR] SHIM_API_KEY is required but missing; shim startup skipped." >&2
  else
    ( while true; do start_shim; sleep 5; done ) &
  fi
fi

############################################
# Probes (asynch) & tail
############################################
command -v curl >/dev/null 2>&1 || (apt-get update && apt-get install -y curl >/dev/null 2>&1 || true)
( until curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null 2>&1; do sleep 1; done; echo "[Probe] ComfyUI ready."; ) &
( until curl -fsS "http://127.0.0.1:${SHIM_PORT}/docs" >/dev/null 2>&1; do sleep 1; done; echo "[Probe] Shim ready."; ) &

touch "$COMFY_LOG" "$JUPYTER_LOG" "$SHIM_LOG"
tail -F "$COMFY_LOG" "$JUPYTER_LOG" "$SHIM_LOG"
