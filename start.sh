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
JUPYTER_TOKEN="${JUPYTER_TOKEN:-}"                # laisser vide si tu veux password-only
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"          # ex: kylee123 (hashé ci-dessous)
JUPYTER_PASSWORD_HASH="${JUPYTER_PASSWORD_HASH:-}"
JUPYTER_ALLOW_ORIGIN_PAT="${JUPYTER_ALLOW_ORIGIN_PAT:-.*runpod\.net}"
FORCE_JUPYTER_RESET="${FORCE_JUPYTER_RESET:-0}"   # 1 pour régénérer la config
JUPYTER_THEME="${JUPYTER_THEME:-JupyterLab Dark}" # "JupyterLab Dark" (défaut) ou "JupyterLab Light"

COMFY_SHA="${COMFY_SHA:-master}"
SKIP_OPTIONAL_NODES="${SKIP_OPTIONAL_NODES:-1}"   # 0 = installe aussi les optionnels

# Workflow par défaut (copié dans l’UI) + auto-queue optionnelle
DEFAULT_WORKFLOW="${DEFAULT_WORKFLOW:-/workspace/ComfyUI/user/default/workflows/Wan22_I2V_Native_3_stage.json}"
COMFY_AUTO_QUEUE="${COMFY_AUTO_QUEUE:-0}"         # 0 = off, 1 = queue ce workflow au démarrage

# Autoload UI (charge le workflow dans le canvas à l’ouverture)
COMFY_UI_AUTOLOAD="${COMFY_UI_AUTOLOAD:-1}"                 # 1 = active (défaut)
COMFY_UI_AUTOLOAD_ON_EVERY_VISIT="${COMFY_UI_AUTOLOAD_ON_EVERY_VISIT:-0}"  # 1 = recharge à chaque visite

# Crystools (repo principal + fallbacks) + token GH si besoin
CRYSTOOLS_REPO="${CRYSTOOLS_REPO:-https://github.com/crystian/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_1="${CRYSTOOLS_FALLBACK_1:-https://github.com/crystools/ComfyUI-Crystools.git}"
CRYSTOOLS_FALLBACK_2="${CRYSTOOLS_FALLBACK_2:-https://github.com/crystoolsai/ComfyUI-Crystools.git}"
GH_TOKEN="${GH_TOKEN:-}"

COMFY_LOG="${WORKDIR}/logs/comfyui.log"
JUPYTER_LOG="${WORKDIR}/logs/jupyter.log"
METRICS_JSON="${WORKDIR}/logs/boot_metrics.json"

export GIT_TERMINAL_PROMPT=0
export SHELL=/bin/bash

mkdir -p "$WORKDIR" "$PIP_CACHE_DIR" "$WORKDIR/logs" "$WORKDIR/models"
echo "[Init] WORKDIR=$WORKDIR"
echo "[Init] COMFY_DIR=$COMFY_DIR"
echo "[Init] VENV_DIR=$VENV_DIR"
echo "[Init] COMFY_SHA=$COMFY_SHA"
echo "[Init] SKIP_OPTIONAL_NODES=$SKIP_OPTIONAL_NODES"

export PIP_PREFER_BINARY=1
export PIP_NO_BUILD_ISOLATION=1

############################################
# 0) Terminal QoL (style Ubuntu) — idempotent
############################################
if ! grep -q ">>> KYLEE SHELL QoL >>>" ~/.bashrc 2>/dev/null; then
  echo "[Shell] Installing prompt/aliases/bash-completion in ~/.bashrc"
  cat >> ~/.bashrc <<'BASHRC'
# >>> KYLEE SHELL QoL >>>
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
command -v fd  >/dev/null 2>&1 || alias fd='fdfind'
if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi
PROMPT_COMMAND='echo -ne "\033]0;${PWD/#$HOME/~}\007"'
parse_git_branch() { git branch 2>/dev/null | sed -n "/^\*/s/^\* //p"; }
PS1='\[\e[0;36m\][\t]\[\e[0m\] \[\e[1;32m\]\u@\h\[\e[0m\]: \[\e[1;34m\]\w\[\e[0m\] \[\e[0;33m\]$(b=$(parse_git_branch); [ -n "$b" ] && echo "($b)")\[\e[0m\]\n$ '
# <<< KYLEE SHELL QoL <<<
BASHRC
fi

############################################
# 1) Venv persistant
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
# 2) JupyterLab — config persistante (dark/light + password), proxy CORS
############################################
JUPYTER_BIN="${JUPYTER_BIN:-$(command -v jupyter || true)}"
if [ -z "$JUPYTER_BIN" ] && [ -x "$VENV_DIR/bin/jupyter" ]; then JUPYTER_BIN="$VENV_DIR/bin/jupyter"; fi
if [ -z "$JUPYTER_BIN" ] && [ -x "/opt/conda/bin/jupyter" ]; then JUPYTER_BIN="/opt/conda/bin/jupyter"; fi

JCFG_DIR="/workspace/.jupyter"
mkdir -p "$JCFG_DIR/lab/user-settings/@jupyterlab/apputils-extension" "$JCFG_DIR/lab/user-settings/@jupyterlab/terminal-extension" "$JCFG_DIR/runtime"

# Assure que Jupyter lise la config persistante
[ -e ~/.jupyter ] || ln -s "$JCFG_DIR" ~/.jupyter
[ -L ~/.jupyter ] || { rm -rf ~/.jupyter; ln -s "$JCFG_DIR" ~/.jupyter; }

# Hash si password clair fourni et pas de hash explicite
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

# Cookie secret persistant
[ -f "$JCFG_DIR/jupyter_cookie_secret" ] || head -c 32 /dev/urandom > "$JCFG_DIR/jupyter_cookie_secret"

# (Re)génère la config si absente ou si demandé
if [ "${FORCE_JUPYTER_RESET}" = "1" ] || [ ! -f "$JCFG_DIR/jupyter_server_config.py" ]; then
  echo "[Jupyter] Writing persistent config to $JCFG_DIR/jupyter_server_config.py"
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

# Écrit/actualise les préférences UI (thème + terminal)
cat > "$JCFG_DIR/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings" <<JSON
{ "theme": "${JUPYTER_THEME}" }
JSON
cat > "$JCFG_DIR/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings" <<'JSON'
{ "theme": "dark", "fontSize": 14, "cursorBlink": true, "scrollback": 10000 }
JSON

# Lancement Jupyter avec config persistante
if [ -n "$JUPYTER_BIN" ]; then
  echo "[Run] Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT} using ${JUPYTER_BIN}"
  nohup "$JUPYTER_BIN" lab \
    --no-browser \
    --allow-root \
    --config="${JCFG_DIR}/jupyter_server_config.py" \
    > "${JUPYTER_LOG}" 2>&1 &
else
  echo "[WARN] Jupyter binary not found; skipping Jupyter start."
fi

sleep 1 || true
echo "[Info] Jupyter log tail hint: tail -n 50 ${JUPYTER_LOG}"

############################################
# 3) ComfyUI (clone/pin + deps)
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
# 4) SageAttention (build)
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
  pip install -e . --no-build-isolatio
n --cache-dir "$PIP_CACHE_DIR" || true
fi

############################################
# 5) Custom nodes — REQUIS: Crystools & Manager (+ autres requis)
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
        if [ "$required" = "1" ]; then echo "[Node][ERROR] required $folder failed — continuing"; fi
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

# Requis pour le workflow
clone_node https://github.com/kijai/ComfyUI-KJNodes.git                    ComfyUI-KJNodes              1
clone_node https://github.com/city96/ComfyUI-GGUF.git                      ComfyUI-GGUF                1
clone_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git     ComfyUI-VideoHelperSuite    1
clone_node https://github.com/Fannovel16/comfyui-frame-interpolation.git   comfyui-frame-interpolation 1

# Crystools — REQUIS (repo principal + fallbacks)
clone_node "$CRYSTOOLS_REPO"  ComfyUI-Crystools 1
[ -d ComfyUI-Crystools/.git ] || clone_node "$CRYSTOOLS_FALLBACK_1" ComfyUI-Crystools 1
[ -d ComfyUI-Crystools/.git ] || clone_node "$CRYSTOOLS_FALLBACK_2" ComfyUI-Crystools 1
[ -f "ComfyUI-Crystools/requirements.txt" ] && pip install -r ComfyUI-Crystools/requirements.txt --cache-dir "$PIP_CACHE_DIR" || true

# Manager — REQUIS
clone_node https://github.com/ltdrdata/ComfyUI-Manager.git                 ComfyUI-Manager             1

# Optionnels (activés si SKIP_OPTIONAL_NODES=0)
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
# 6.5) Workflow par défaut — copie vers l’UI + args Comfy
############################################
WF_DST_DIR="${COMFY_DIR}/user/default/workflows"
mkdir -p "${WF_DST_DIR}"

COMFY_EXTRA_ARGS=()
if [ -f "${DEFAULT_WORKFLOW}" ]; then
  cp -f "${DEFAULT_WORKFLOW}" "${WF_DST_DIR}/_auto_default.json"
  echo "[Workflow] Copied default workflow to ${WF_DST_DIR}/_auto_default.json"
  if [ "${COMFY_AUTO_QUEUE}" = "1" ]; then
    COMFY_EXTRA_ARGS+=(--infinite-queue-at-startup "${DEFAULT_WORKFLOW}")
    echo "[Workflow] Auto-queue enabled for: ${DEFAULT_WORKFLOW}"
  fi
else
  echo "[Workflow][WARN] DEFAULT_WORKFLOW not found at: ${DEFAULT_WORKFLOW}"
fi

############################################
# 6.6) Trouver le vrai WEB ROOT et installer l’extension là
############################################
# Détecte le répertoire "static" réellement servi par ComfyUI (frontend package)
WEB_ROOT="$(python - <<'PY'
try:
    import importlib.resources as ir
    p = ir.files('comfyui_frontend_package') / 'static'
    print(str(p))
except Exception as e:
    print('')
PY
)"
if [ -z "$WEB_ROOT" ] || [ ! -d "$WEB_ROOT" ]; then
  # Fallback: ancien chemin dans le repo (peu probable avec le frontend pip)
  WEB_ROOT="${COMFY_DIR}/web"
fi
echo "[WebRoot] Using: $WEB_ROOT"

############################################
# 6.7) UI Autoload extension (installée dans $WEB_ROOT/extensions)
############################################
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
    if (!everyVisit && localStorage.getItem(FLAG) === "1") {
      console.log("[Kylee-Autoload] Already loaded once for this browser; skipping.");
      return;
    }

    const candidates = [
      "/extensions/kylee-autoload/default_workflow.json",
      "/user/default/workflows/_auto_default.json",
      "/ComfyUI/user/default/workflows/_auto_default.json"
    ];

    let wf = null, lastErr = null;
    for (const url of candidates) {
      try {
        const r = await fetch(url, { cache: "no-store" });
        if (r.ok) { wf = await r.json(); console.log("[Kylee-Autoload] Loaded:", url); break; }
        lastErr = `HTTP ${r.status}`;
      } catch (e) { lastErr = e; }
    }
    if (!wf) {
      console.warn("[Kylee-Autoload] Could not fetch workflow JSON. Last error:", lastErr);
      return;
    }

    await app.loadGraphData(wf);
    console.log("[Kylee-Autoload] Default workflow loaded into canvas.");
    if (!everyVisit) localStorage.setItem(FLAG, "1");
  } catch (e) {
    console.warn("[Kylee-Autoload] Failed:", e);
  }
}

app.registerExtension({
  name: "kylee-autoload",
  async setup() {
    try { await api.ready; } catch {}
    const every = (window?.KYLEE_AUTOLOAD_EVERY_VISIT === true);
    setTimeout(() => loadDefaultWorkflow({ everyVisit: every }), 250);
  }
});
JS

  if [ "${COMFY_UI_AUTOLOAD_ON_EVERY_VISIT}" = "1" ]; then
    echo 'window.KYLEE_AUTOLOAD_EVERY_VISIT = true;' > "${EXT_DIR}/preload.js"
  else
    echo 'window.KYLEE_AUTOLOAD_EVERY_VISIT = false;' > "${EXT_DIR}/preload.js"
  fi

  echo "[UI] Autoload extension installed at ${EXT_DIR}"
else
  echo "[UI] Autoload extension is disabled or workflow copy missing."
fi

############################################
# 7) Lancer ComfyUI + mesurer le temps jusqu’à ready
############################################
touch "$COMFY_LOG" "$JUPYTER_LOG"

start_comfy() {
  echo "[Run] Starting ComfyUI on ${COMFY_HOST}:${COMFY_PORT} (--disable-auto-launch + --use-sage-attention)"
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

# Probe localhost pour mesurer le temps de disponibilité
(
  echo "[Probe] Waiting for ComfyUI to answer on 127.0.0.1:${COMFY_PORT}"
  until curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null 2>&1; do
    sleep 1
  done
  BOOT_T1=$(date +%s)
  BOOT_SECONDS=$(( BOOT_T1 - BOOT_T0 ))
  echo "[Metrics] ComfyUI ready in ${BOOT_SECONDS}s since start.sh"
  printf '{\n  "start_epoch": %s,\n  "ready_epoch": %s,\n  "comfy_ready_seconds": %s\n}\n' \
    "$BOOT_T0" "$BOOT_T1" "$BOOT_SECONDS" > "$METRICS_JSON"
) &

echo "[Run] Tailing logs"
tail -F "$COMFY_LOG" "$JUPYTER_LOG"
