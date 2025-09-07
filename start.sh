#!/usr/bin/env bash
# Hardened start: watchdog, robust clones, foreground log tail (RunPod-ready, root)
set -uo pipefail

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
JUPYTER_TOKEN="${JUPYTER_TOKEN:-}"                 # si vide et password fourni, on désactive le token
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"           # mot de passe en clair (ex: kylee123)
JUPYTER_PASSWORD_HASH="${JUPYTER_PASSWORD_HASH:-}" # hash argon2 (si déjà fourni)
JUPYTER_ALLOW_ORIGIN_PAT="${JUPYTER_ALLOW_ORIGIN_PAT:-.*runpod\.net}"

COMFY_SHA="${COMFY_SHA:-master}"
SKIP_OPTIONAL_NODES="${SKIP_OPTIONAL_NODES:-1}"     # 1 = skip optionnels (défaut), 0 = installer optionnels

# Crystools — repo principal (fourni) + fallbacks (configurables)
CRYSTOOLS_REPO="${CRYSTOOLS_REPO:-https://github.com/crystian/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_1="${CRYSTOOLS_FALLBACK_1:-https://github.com/crystools/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_2="${CRYSTOOLS_FALLBACK_2:-https://github.com/crystoolsai/ComfyUI-Crystools.git}"
GH_TOKEN="${GH_TOKEN:-}" # si besoin d’auth GitHub (privé / rate limit), sinon laisser vide

COMFY_LOG="${WORKDIR}/logs/comfyui.log"
JUPYTER_LOG="${WORKDIR}/logs/jupyter.log"
export GIT_TERMINAL_PROMPT=0

############################################
# Contexte
############################################
mkdir -p "$WORKDIR" "$PIP_CACHE_DIR" "$WORKDIR/logs" "$WORKDIR/models"
echo "[Init] WORKDIR=$WORKDIR"
echo "[Init] COMFY_DIR=$COMFY_DIR"
echo "[Init] VENV_DIR=$VENV_DIR"
echo "[Init] COMFY_SHA=$COMFY_SHA"
echo "[Init] SKIP_OPTIONAL_NODES=$SKIP_OPTIONAL_NODES"

# Pip plus rapide/robuste
export PIP_PREFER_BINARY=1
export PIP_NO_BUILD_ISOLATION=1

############################################
# 0) Confort Terminal (style Ubuntu) — idempotent
############################################
if ! grep -q ">>> KYLEE SHELL QoL >>>" ~/.bashrc 2>/dev/null; then
  echo "[Shell] Installing prompt/aliases/bash-completion in ~/.bashrc"
  cat >> ~/.bashrc <<'BASHRC'
# >>> KYLEE SHELL QoL >>>
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi
PROMPT_COMMAND='echo -ne "\033]0;${PWD/#$HOME/~}\007"'
parse_git_branch() { git branch 2>/dev/null | sed -n "/^\*/s/^\* //p"; }
PS1='\[\e[0;36m\][\t]\[\e[0m\] \[\e[1;32m\]\u@\h\[\e[0m\]: \[\e[1;34m\]\w\[\e[0m\] \[\e[0;33m\]$(b=$(parse_git_branch); [ -n "$b" ] && echo "($b)")\[\e[0m\]\n$ '
# <<< KYLEE SHELL QoL <<<
BASHRC
fi

############################################
# 1) Venv persistant (hérite des paquets système)
############################################
if [ ! -d "$VENV_DIR" ]; then
  echo "[Venv] Creating virtualenv at $VENV_DIR (system site-packages)"
  python3 -m venv --system-site-packages "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate" || true
python -V || true
pip install --upgrade pip wheel --cache-dir "$PIP_CACHE_DIR" || true

############################################
# 2) JupyterLab (auth password/token + CORS proxy) — root OK
############################################
JUPYTER_BIN="${JUPYTER_BIN:-$(command -v jupyter || true)}"
if [ -z "$JUPYTER_BIN" ] && [ -x "$VENV_DIR/bin/jupyter" ]; then JUPYTER_BIN="$VENV_DIR/bin/jupyter"; fi
if [ -z "$JUPYTER_BIN" ] && [ -x "/opt/conda/bin/jupyter" ]; then JUPYTER_BIN="/opt/conda/bin/jupyter"; fi

# Hash auto si password clair fourni
if [ -n "$JUPYTER_PASSWORD" ] && [ -z "$JUPYTER_PASSWORD_HASH" ]; then
  echo "[Auth] Generating Jupyter password hash from JUPYTER_PASSWORD"
  JUPYTER_PASSWORD_HASH="$(
    JUP_PLAIN="$JUPYTER_PASSWORD" python - <<'PY'
from jupyter_server.auth import passwd
import os
pwd = os.environ.get('JUP_PLAIN','')
print(passwd(pwd) if pwd else '', end='')
PY
  )"
fi

if [ -n "$JUPYTER_BIN" ]; then
  echo "[Run] Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT} using ${JUPYTER_BIN}"
  EXTRA_AUTH_ARGS=()
  if [ -n "$JUPYTER_PASSWORD_HASH" ]; then
    EXTRA_AUTH_ARGS+=(--ServerApp.password="${JUPYTER_PASSWORD_HASH}")
    EXTRA_AUTH_ARGS+=(--ServerApp.token='')
  elif [ -n "$JUPYTER_TOKEN" ]; then
    EXTRA_AUTH_ARGS+=(--ServerApp.token="${JUPYTER_TOKEN}")
  fi

  nohup "$JUPYTER_BIN" lab \
    --no-browser \
    --allow-root \
    --ServerApp.ip="${JUPYTER_IP}" \
    --ServerApp.port="${JUPYTER_PORT}" \
    --ServerApp.root_dir="${WORKDIR}" \
    --ServerApp.trust_xheaders=True \
    --ServerApp.allow_remote_access=True \
    --ServerApp.allow_origin_pat="${JUPYTER_ALLOW_ORIGIN_PAT}" \
    "${EXTRA_AUTH_ARGS[@]}" \
    > "${JUPYTER_LOG}" 2>&1 &
else
  echo "[WARN] Jupyter binary not found; skipping Jupyter start."
fi

sleep 1 || true
echo "[Info] Jupyter log tail hint: tail -n 50 ${JUPYTER_LOG}"

############################################
# 3) ComfyUI clone/pin + deps légères
############################################
if [ ! -d "$COMFY_DIR/.git" ]; then
  echo "[ComfyUI] Cloning repository"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR" || true
fi
if [ -d "$COMFY_DIR/.git" ]; then
  cd "$COMFY_DIR"
  git fetch --all --tags || true
  git checkout "$COMFY_SHA" 2>/dev/null || git checkout origin/"$COMFY_SHA" || true
  if [ -f requirements.txt ]; then
    echo "[PIP] Installing ComfyUI requirements"
    pip install -r requirements.txt --cache-dir "$PIP_CACHE_DIR" || true
  fi
else
  echo "[WARN] ComfyUI repo missing; will try to run anyway."
fi

############################################
# 4) SageAttention 2.2 (build depuis le repo officiel)
############################################
SAGE_SRC_DIR="${WORKDIR}/SageAttention"
if [ ! -d "${SAGE_SRC_DIR}/.git" ]; then
  echo "[Sage] Cloning SageAttention"
  git clone https://github.com/thu-ml/SageAttention.git "${SAGE_SRC_DIR}" || true
fi
if [ -d "${SAGE_SRC_DIR}" ]; then
  echo "[Sage] Building/Installing SageAttention from source"
  export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32
  cd "${SAGE_SRC_DIR}" || true
  pip install -e . --no-build-isolation --cache-dir "$PIP_CACHE_DIR" || true
fi

############################################
# 5) Custom nodes (robustes) — Crystools & Manager **REQUIS**
############################################
mkdir -p "$COMFY_DIR/custom_nodes"
cd "$COMFY_DIR/custom_nodes" 2>/dev/null || true

clone_node () {
  local repo="$1" folder="$2" required="$3" tries=0
  local auth=()
  [ -n "$GH_TOKEN" ] && auth=(-c http.extraheader="AUTHORIZATION: bearer ${GH_TOKEN}")
  if [ ! -d "$folder/.git" ] && [ ! -d "$folder" ]; then
    echo "[Node] ${folder} <- ${repo}"
    until git "${auth[@]}" clone --depth 1 "$repo" "$folder"; do
      tries=$((tries+1)); echo "[Node][WARN] clone failed ($tries) for $folder"
      if [ "$tries" -ge 3 ]; then
        if [ "$required" = "1" ]; then echo "[Node][ERROR] required $folder failed — skipping (continuing)"; fi
        break
      fi
      sleep 3
    done
  fi
  if [ -d "$folder" ] && [ -f "$folder/requirements.txt" ]; then
    echo "[PIP] Installing deps for $folder"
    pip install -r "$folder/requirements.txt" --cache-dir "$PIP_CACHE_DIR" || true
  fi
}

# REQUIS (workflow de base)
clone_node https://github.com/kijai/ComfyUI-KJNodes.git                 ComfyUI-KJNodes           1
clone_node https://github.com/city96/ComfyUI-GGUF.git                   ComfyUI-GGUF             1
clone_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git  ComfyUI-VideoHelperSuite 1
clone_node https://github.com/Fannovel16/comfyui-frame-interpolation.git comfyui-frame-interpolation 1

# Crystools — **REQUIS**, avec fallbacks
clone_node "$CRYSTOOLS_REPO"  ComfyUI-Crystools 1
if [ ! -d "ComfyUI-Crystools/.git" ]; then
  clone_node "$CRYSTOOLS_FALLBACK_1" ComfyUI-Crystools 1
fi
if [ ! -d "ComfyUI-Crystools/.git" ]; then
  clone_node "$CRYSTOOLS_FALLBACK_2" ComfyUI-Crystools 1
fi
[ -f "ComfyUI-Crystools/requirements.txt" ] && pip install -r ComfyUI-Crystools/requirements.txt --cache-dir "$PIP_CACHE_DIR" || true

# Manager — **REQUIS**
clone_node https://github.com/ltdrdata/ComfyUI-Manager.git              ComfyUI-Manager          1

# Optionnels (installés seulement si SKIP_OPTIONAL_NODES=0)
if [ "${SKIP_OPTIONAL_NODES}" = "0" ]; then
  clone_node https://github.com/cubiq/ComfyUI_Unload_Model.git         ComfyUI_Unload_Model     0
  clone_node https://github.com/rgthree/rgthree-comfy.git              rgthree-comfy            0
  clone_node https://github.com/WASasquatch/was-node-suite-comfyui.git was-node-suite-comfyui   0
  clone_node https://github.com/cubiq/ComfyUI_essentials.git           ComfyUI_essentials       0
  clone_node https://github.com/cubiq/ComfyUI-Easy-Use.git             ComfyUI-Easy-Use         0
fi

############################################
# 6) Dossiers modèles (symlink)
############################################
cd "$COMFY_DIR" 2>/dev/null || true
mkdir -p /workspace/models
[ -d "$COMFY_DIR" ] && [ ! -L "$COMFY_DIR/models" ] && { rm -rf "$COMFY_DIR/models"; ln -s /workspace/models "$COMFY_DIR/models"; }

############################################
# 7) Watchdog ComfyUI + tail logs en foreground
############################################
touch "$COMFY_LOG" "$JUPYTER_LOG"
start_comfy() {
  echo "[Run] Starting ComfyUI on ${COMFY_HOST}:${COMFY_PORT} (--disable-auto-launch + --use-sage-attention)"
  ( "$VENV_DIR/bin/python" "$COMFY_DIR/main.py" \
      --listen "$COMFY_HOST" \
      --port "$COMFY_PORT" \
      --disable-auto-launch \
      --use-sage-attention \
      --log-stdout \
      2>&1 | tee -a "$COMFY_LOG" ) || true
  echo "[Run] ComfyUI exited with code $? — will retry in 5s"
}
( while true; do start_comfy; sleep 5; done ) &
echo "[Run] Tailing logs"
tail -F "$COMFY_LOG" "$JUPYTER_LOG"
