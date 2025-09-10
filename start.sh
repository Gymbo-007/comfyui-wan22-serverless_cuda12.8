#!/usr/bin/env bash
set -uo pipefail

echo "======================================"
echo "[INIT] Script démarré à $(date)"
echo "[INIT] PID: $$"
echo "[INIT] User: $(whoami) (UID: $EUID)"
echo "======================================"

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
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"
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

SHIM_ENABLED="${SHIM_ENABLED:-1}"
SHIM_HOST="${SHIM_HOST:-0.0.0.0}"
SHIM_PORT="${SHIM_PORT:-8080}"
SHIM_DIR="${SHIM_DIR:-/opt/shim}"
SHIM_WORKFLOW_PATH="${SHIM_WORKFLOW_PATH:-${DEFAULT_WORKFLOW}}"

# SSH Variables
SSH_ENABLE="${SSH_ENABLE:-1}"
SSH_PORT="${SSH_PORT:-2222}"
ROOT_PASSWORD="${ROOT_PASSWORD:-RunPod123!}"
SSHD_LOG="${WORKDIR}/logs/sshd.log"

export GIT_TERMINAL_PROMPT=0
export SHELL=/bin/bash

mkdir -p "$WORKDIR" "$PIP_CACHE_DIR" "$WORKDIR/logs" "$WORKDIR/models"

echo "[Init] Configuration:"
echo "  - WORKDIR=$WORKDIR"
echo "  - COMFY_DIR=$COMFY_DIR"
echo "  - VENV_DIR=$VENV_DIR"
echo "  - COMFY_SHA=$COMFY_SHA"
echo "  - SKIP_OPTIONAL_NODES=$SKIP_OPTIONAL_NODES"
echo "[Init] SSH Configuration:"
echo "  - SSH_ENABLE=$SSH_ENABLE"
echo "  - SSH_PORT=$SSH_PORT"
echo "  - ROOT_PASSWORD=[SET]"

# Environnement RunPod
echo "[RunPod] Environment check:"
echo "  - RUNPOD_POD_ID: ${RUNPOD_POD_ID:-not_set}"
echo "  - RUNPOD_PUBLIC_IP: ${RUNPOD_PUBLIC_IP:-not_set}"
echo "  - RUNPOD_TCP_PORT_22: ${RUNPOD_TCP_PORT_22:-not_set}"
echo "  - RUNPOD_TCP_PORT_2222: ${RUNPOD_TCP_PORT_2222:-not_set}"

export PIP_PREFER_BINARY=1
export PIP_NO_BUILD_ISOLATION=1

############################################
# 0) Terminal QoL (style Ubuntu)
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
# <<< KYLEE SHELL QoL
BASHRC
fi

############################################
# 0.5) SSH Setup avec diagnostic complet
############################################
setup_ssh() {
  echo "[SSH] ========== DÉBUT SETUP SSH =========="
  echo "[SSH] Timestamp: $(date)"
  echo "[SSH] User: $(whoami), UID: $EUID"
  
  # Vérification des variables
  if [ -z "$ROOT_PASSWORD" ] || [ "$ROOT_PASSWORD" = "undefined" ]; then
    echo "[SSH][ERROR] ROOT_PASSWORD non défini ou invalide"
    return 1
  fi
  
  # Check si SSH déjà installé
  echo "[SSH] Vérification installation existante..."
  if command -v sshd >/dev/null 2>&1; then
    echo "[SSH] sshd déjà installé: $(which sshd)"
    sshd -V 2>&1 | head -1
  else
    echo "[SSH] sshd non trouvé, installation nécessaire"
  fi
  
  # Installation OpenSSH
  echo "[SSH] Mise à jour des paquets..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq 2>&1 | tail -3
  
  echo "[SSH] Installation openssh-server..."
  apt-get install -y openssh-server net-tools lsof 2>&1 | grep -E "(Setting up|Processing|Unpacking)" | tail -5
  
  # Vérification post-installation
  if ! command -v sshd >/dev/null 2>&1; then
    echo "[SSH][ERROR] sshd non disponible après installation"
    return 1
  fi
  echo "[SSH] sshd installé: $(which sshd)"
  
  echo "[SSH] Création des répertoires..."
  mkdir -p /var/run/sshd /etc/ssh /run/sshd ~/.ssh
  chmod 700 ~/.ssh
  
  # Générer les clés hôte
  echo "[SSH] Génération des clés hôte..."
  ssh-keygen -A 2>&1 | head -5
  ls -la /etc/ssh/ssh_host_* 2>/dev/null | head -3
  
  # Configuration sshd
  echo "[SSH] Écriture de la configuration sshd..."
  cat > /etc/ssh/sshd_config <<EOF
# Configuration SSH pour RunPod
Port ${SSH_PORT}
ListenAddress 0.0.0.0
Protocol 2

# Clés hôte
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentification
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
StrictModes no
AuthorizedKeysFile .ssh/authorized_keys

# Sécurité basique
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*

# Performance
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 6
MaxSessions 10

# Logging
SyslogFacility AUTH
LogLevel INFO
PidFile /var/run/sshd.pid

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
  
  # Définir le mot de passe root
  echo "[SSH] Configuration du mot de passe root..."
  echo "root:${ROOT_PASSWORD}" | chpasswd
  if [ $? -eq 0 ]; then
    echo "[SSH] Mot de passe root configuré avec succès"
  else
    echo "[SSH][ERROR] Échec configuration mot de passe"
  fi
  
  # Test de configuration
  echo "[SSH] Test de la configuration..."
  sshd -t -f /etc/ssh/sshd_config
  if [ $? -ne 0 ]; then
    echo "[SSH][ERROR] Configuration invalide"
    return 1
  fi
  
  # Arrêter les instances existantes
  echo "[SSH] Arrêt des instances sshd existantes..."
  pkill -f "sshd" 2>/dev/null || true
  sleep 2
  
  # Créer le fichier de log
  touch "${SSHD_LOG}"
  
  # Démarrer sshd en mode daemon normal (sans -D)
  echo "[SSH] Démarrage de sshd sur port ${SSH_PORT}..."
  /usr/sbin/sshd -f /etc/ssh/sshd_config -E "${SSHD_LOG}"
  
  # Attendre le démarrage
  sleep 3
  
  # Vérifications finales
  echo "[SSH] Vérifications post-démarrage..."
  
  # Check processus
  if pgrep -f "sshd" > /dev/null; then
    echo "[SSH] ✓ Processus sshd actif (PID: $(pgrep -f sshd | head -1))"
  else
    echo "[SSH] ✗ Processus sshd non trouvé"
    tail -20 "${SSHD_LOG}" 2>/dev/null
    return 1
  fi
  
  # Check port
  echo "[SSH] Ports en écoute:"
  lsof -i :${SSH_PORT} 2>/dev/null || netstat -tlnp 2>/dev/null | grep :${SSH_PORT} || ss -tlnp | grep :${SSH_PORT}
  
  # Check processus sshd
  echo "[SSH] Processus SSH actifs:"
  ps aux | grep -E "[s]shd" | head -3
  
  echo "[SSH] ========================================="
  echo "[SSH][SUCCESS] SSH configuré avec succès!"
  
  # Afficher les informations de connexion appropriées
  if [ -n "${RUNPOD_PUBLIC_IP:-}" ] && [ -n "${RUNPOD_TCP_PORT_2222:-}" ]; then
    echo "[SSH] Connexion externe: ssh root@${RUNPOD_PUBLIC_IP} -p ${RUNPOD_TCP_PORT_2222}"
  elif [ -n "${RUNPOD_PUBLIC_IP:-}" ] && [ -n "${RUNPOD_TCP_PORT_22:-}" ]; then
    echo "[SSH] Connexion externe: ssh root@${RUNPOD_PUBLIC_IP} -p ${RUNPOD_TCP_PORT_22}"
  else
    echo "[SSH] Connexion locale: ssh root@localhost -p ${SSH_PORT}"
  fi
  
  echo "[SSH] Mot de passe: ${ROOT_PASSWORD}"
  echo "[SSH] ========================================="
  
  # Log dans le fichier
  echo "[$(date)] SSH démarré sur port ${SSH_PORT}" >> "${SSHD_LOG}"
  
  return 0
}

# Fonction pour maintenir SSH en vie
keep_ssh_alive() {
  while true; do
    if ! pgrep -f "sshd" > /dev/null; then
      echo "[SSH] sshd n'est plus actif, redémarrage..."
      /usr/sbin/sshd -f /etc/ssh/sshd_config -E "${SSHD_LOG}"
    fi
    sleep 30
  done
}

# APPEL SSH PRINCIPAL
echo ""
echo "======================================"
echo "[MAIN] Vérification activation SSH..."
echo "======================================"

if [ "${SSH_ENABLE}" = "1" ]; then
  echo "[MAIN] SSH activé, lancement de la configuration..."
  
  if setup_ssh; then
    echo "[MAIN] Configuration SSH terminée avec succès"
    # Lancer le gardien SSH en arrière-plan
    keep_ssh_alive &
  else
    echo "[MAIN] Configuration SSH échouée (code: $?)"
    echo "[MAIN] Consultation des logs:"
    [ -f "${SSHD_LOG}" ] && tail -10 "${SSHD_LOG}"
  fi
else
  echo "[MAIN] SSH désactivé (SSH_ENABLE != 1)"
fi

echo ""
echo "======================================"
echo "[MAIN] Suite du démarrage..."
echo "======================================"

############################################
# 1) Venv persistant
############################################
if [ ! -d "$VENV_DIR" ]; then
  echo "[Venv] Creating virtualenv at $VENV_DIR"
  python3 -m venv --system-site-packages "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate" || true
python -V || true
pip install --upgrade pip wheel --cache-dir "$PIP_CACHE_DIR" || true

############################################
# 2) JupyterLab
############################################
JUPYTER_BIN="${JUPYTER_BIN:-$(command -v jupyter || true)}"
if [ -z "$JUPYTER_BIN" ] && [ -x "$VENV_DIR/bin/jupyter" ]; then JUPYTER_BIN="$VENV_DIR/bin/jupyter"; fi
if [ -z "$JUPYTER_BIN" ] && [ -x "/opt/conda/bin/jupyter" ]; then JUPYTER_BIN="/opt/conda/bin/jupyter"; fi

JCFG_DIR="/workspace/.jupyter"
mkdir -p "$JCFG_DIR/lab/user-settings/@jupyterlab/apputils-extension" "$JCFG_DIR/lab/user-settings/@jupyterlab/terminal-extension" "$JCFG_DIR/runtime"

[ -e ~/.jupyter ] || ln -s "$JCFG_DIR" ~/.jupyter
[ -L ~/.jupyter ] || { rm -rf ~/.jupyter; ln -s "$JCFG_DIR" ~/.jupyter; }

if [ -n "$JUPYTER_PASSWORD" ] && [ -z "$JUPYTER_PASSWORD_HASH" ]; then
  echo "[Auth] Generating Jupyter password hash"
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
  echo "[Jupyter] Writing config"
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
  echo "[Run] Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT}"
  nohup "$JUPYTER_BIN" lab \
    --no-browser \
    --allow-root \
    --config="${JCFG_DIR}/jupyter_server_config.py" \
    > "${JUPYTER_LOG}" 2>&1 &
fi

############################################
# 3) ComfyUI
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
fi

############################################
# 3.5) Install shim dependencies
############################################
if [ -f "${SHIM_DIR}/requirements.txt" ]; then
  echo "[PIP] Installing shim requirements"
  pip install -r "${SHIM_DIR}/requirements.txt" --cache-dir "$PIP_CACHE_DIR" || true
fi

############################################
# 4) SageAttention
############################################
SAGE_SRC_DIR="${WORKDIR}/SageAttention"
if [ ! -d "${SAGE_SRC_DIR}/.git" ]; then
  echo "[Sage] Cloning SageAttention"
  git clone https://github.com/thu-ml/SageAttention.git "${SAGE_SRC_DIR}" || true
fi
if [ -d "${SAGE_SRC_DIR}" ]; then
  echo "[Sage] Building SageAttention"
  export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32
  cd "${SAGE_SRC_DIR}" || true
  pip install -e . --no-build-isolation --cache-dir "$PIP_CACHE_DIR" || true
else
  echo "[Sage] SageAttention already installed — skipping."
fi

############################################
# 5) Custom nodes
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
        if [ "$required" = "1" ]; then echo "[Node][ERROR] required $folder failed"; fi
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

# Nodes requis
clone_node https://github.com/kijai/ComfyUI-KJNodes.git                    ComfyUI-KJNodes              1
clone_node https://github.com/city96/ComfyUI-GGUF.git                      ComfyUI-GGUF                1
clone_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git     ComfyUI-VideoHelperSuite    1
clone_node https://github.com/Fannovel16/comfyui-frame-interpolation.git   comfyui-frame-interpolation 1

clone_node "$CRYSTOOLS_REPO"  ComfyUI-Crystools 1
[ -d ComfyUI-Crystools/.git ] || clone_node "$CRYSTOOLS_FALLBACK_1" ComfyUI-Crystools 1
[ -d ComfyUI-Crystools/.git ] || clone_node "$CRYSTOOLS_FALLBACK_2" ComfyUI-Crystools 1

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
  echo "[Workflow] Copied default workflow"
  if [ "${COMFY_AUTO_QUEUE}" = "1" ]; then
    COMFY_EXTRA_ARGS+=(--infinite-queue-at-startup "${DEFAULT_WORKFLOW}")
  fi
fi

############################################
# 6.6) Web root
############################################
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
  WEB_ROOT="${COMFY_DIR}/web"
fi
echo "[WebRoot] Using: $WEB_ROOT"

############################################
# 6.7) UI Autoload extension
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

  echo "[UI] Autoload extension installed"
fi

############################################
# 7) Lancer ComfyUI
############################################
touch "$COMFY_LOG" "$JUPYTER_LOG" "$SHIM_LOG" "$SSHD_LOG" 2>/dev/null || true

start_comfy() {
  echo "[Run] Starting ComfyUI on ${COMFY_HOST}:${COMFY_PORT}"
  
  local comfy_args=("--listen" "$COMFY_HOST" "--port" "$COMFY_PORT" "--disable-auto-launch")
  
  if python -c "import torch; print(torch.cuda.is_available())" 2>/dev/null | grep -q "True"; then
    echo "[ComfyUI] CUDA detected, using GPU mode"
    comfy_args+=("--use-sage-attention")
  else
    echo "[ComfyUI] No CUDA detected, using CPU mode"
    comfy_args+=("--cpu")
  fi
  
  comfy_args+=("${COMFY_EXTRA_ARGS[@]}")
  comfy_args+=("--log-stdout")
  
  ( "$VENV_DIR/bin/python" "$COMFY_DIR/main.py" "${comfy_args[@]}" 2>&1 | tee -a "$COMFY_LOG" ) || true
  echo "[Run] ComfyUI exited with code $?"
}
( while true; do start_comfy; sleep 5; done ) &

# Probe
(
  echo "[Probe] Waiting for ComfyUI on 127.0.0.1:${COMFY_PORT}"
  until curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null 2>&1; do
    sleep 1
  done
  BOOT_T1=$(date +%s)
  BOOT_SECONDS=$(( BOOT_T1 - BOOT_T0 ))
  echo "[Metrics] ComfyUI ready in ${BOOT_SECONDS}s"
  printf '{\n  "start_epoch": %s,\n  "ready_epoch": %s,\n  "comfy_ready_seconds": %s\n}\n' \
    "$BOOT_T0" "$BOOT_T1" "$BOOT_SECONDS" > "$METRICS_JSON"
) &

############################################
# 8) Start Shim
############################################
start_shim() {
  echo "[Run] Starting Shim on ${SHIM_HOST}:${SHIM_PORT}"
  (
    export COMFY_PORT COMFY_HOST
    export COMFY_API_URL="${COMFY_API_URL:-http://127.0.0.1:${COMFY_PORT}}"
    export SHIM_WORKFLOW_PATH
    cd "${SHIM_DIR}" || exit 0
    "${VENV_DIR}/bin/uvicorn" app:app --host "$SHIM_HOST" --port "$SHIM_PORT" 2>&1 | tee -a "$SHIM_LOG"
  ) || true
}

if [ "${SHIM_ENABLED}" = "1" ]; then
  ( while true; do start_shim; sleep 5; done ) &
fi

echo "[Run] Tailing logs"
tail -F "$COMFY_LOG" "$JUPYTER_LOG" "$SHIM_LOG" "$SSHD_LOG" 2>/dev/null