# Image "warm" : ComfyUI + deps Shim préinstallés pour un boot très rapide
# CUDA 12.8 runtime → nécessaire pour RTX 50xx + SageAttention 2
FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04

ARG GH_TOKEN=""

ENV DEBIAN_FRONTEND=noninteractive \
    WORKDIR=/workspace \
    VENV_DIR=/workspace/venv \
    PIP_CACHE_DIR=/workspace/.cache/pip \
    COMFY_DIR=/workspace/ComfyUI

# Sys deps de base
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Optional GitHub token support for build-time clones
RUN if [ -n "$GH_TOKEN" ]; then \
      git config --global url."https://${GH_TOKEN}@github.com/".insteadOf "https://github.com/" && \
      git config --global credential.helper ""; \
    fi

# Venv + pip à jour
RUN python3 -m venv $VENV_DIR && \
    $VENV_DIR/bin/pip install --upgrade pip wheel

# JupyterLab (pour acces notebook optionnel)
RUN --mount=type=cache,target=/workspace/.cache/pip \
    bash -lc '$VENV_DIR/bin/pip install jupyterlab'

# ComfyUI (pin "master" par défaut — passe un commit/tag via --build-arg COMFY_SHA=...)
ARG COMFY_SHA=master
RUN git clone --depth 1 --branch ${COMFY_SHA} https://github.com/comfyanonymous/ComfyUI.git $COMFY_DIR
RUN --mount=type=cache,target=/workspace/.cache/pip \
    bash -lc '$VENV_DIR/bin/pip install -r $COMFY_DIR/requirements.txt'

# Shim deps (on ne pin PAS pydantic ici → évite les downgrades lents)
RUN --mount=type=cache,target=/workspace/.cache/pip \
    bash -lc '$VENV_DIR/bin/pip install fastapi uvicorn httpx'

# Ajoute l'app Shim (maintenue dans ./shim/ dans ton repo)
RUN mkdir -p /opt/shim
COPY shim/ /opt/shim/

# Basculer vers bash pour les RUN suivants (pipefail requis)
SHELL ["/bin/bash", "-c"]

# Pré-installe les custom nodes requis en respectant les pins du lock
RUN set -euo pipefail; \
    mkdir -p "$COMFY_DIR/custom_nodes"; \
    cd "$COMFY_DIR/custom_nodes"; \
    LOCK_FILE="/opt/shim/custom_nodes.lock"; \
    if [ -f "$LOCK_FILE" ]; then \
      while read -r NAME REF _; do \
        case "$NAME" in ''|'#'*) continue ;; esac; \
        case "$NAME" in \
          ComfyUI-KJNodes)                 REPO="https://github.com/kijai/ComfyUI-KJNodes.git" ;; \
          ComfyUI-GGUF)                    REPO="https://github.com/city96/ComfyUI-GGUF.git" ;; \
          ComfyUI-VideoHelperSuite)        REPO="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" ;; \
          comfyui-frame-interpolation)     REPO="https://github.com/Fannovel16/comfyui-frame-interpolation.git" ;; \
          ComfyUI-Crystools)               REPO="https://github.com/crystian/ComfyUI-Crystools.git" ;; \
          *) echo "[Docker][WARN] Custom node $NAME non géré lors du build" >&2; continue ;; \
        esac; \
        REPO_CLONE="$REPO"; \
        if [ -n "$GH_TOKEN" ]; then \
          REPO_CLONE="https://${GH_TOKEN}@${REPO#https://}"; \
        fi; \
        echo "[Docker] Clone ${NAME} @ ${REF}"; \
        rm -rf "$NAME"; \
        git clone --filter=blob:none "$REPO_CLONE" "$NAME"; \
        cd "$NAME"; \
        git fetch origin "$REF" --depth 1; \
        git checkout -qf FETCH_HEAD; \
        git rev-parse HEAD > .pinned-ref; \
        if [ -n "$GH_TOKEN" ]; then \
          git remote set-url origin "$REPO"; \
        fi; \
        cd ..; \
      done < "$LOCK_FILE"; \
    fi

# Script de démarrage
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

WORKDIR /workspace
EXPOSE 8188 8080 8888
ENTRYPOINT ["/usr/local/bin/start.sh"]
