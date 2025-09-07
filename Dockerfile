# PyTorch 2.8 + CUDA 12.8 + cuDNN9 (DEVEL, pour compiler SageAttention)
FROM pytorch/pytorch:2.8.0-cuda12.8-cudnn9-devel

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    WORKDIR=/workspace \
    COMFY_DIR=/workspace/ComfyUI \
    VENV_DIR=/workspace/venv \
    PIP_CACHE_DIR=/workspace/.cache/pip \
    COMFY_PORT=8188 \
    COMFY_HOST=0.0.0.0 \
    JUPYTER_PORT=8888 \
    JUPYTER_IP=0.0.0.0 \
    JUPYTER_TOKEN=""

# Packages système utiles (root)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates tzdata \
    python3-venv python3-dev build-essential \
    ffmpeg wget aria2 unzip dos2unix \
 && rm -rf /var/lib/apt/lists/*

# Pré-installer JupyterLab au niveau système
RUN pip install --no-cache-dir jupyterlab

# Créer le workspace
RUN mkdir -p /workspace

# Script de démarrage
COPY start.sh /usr/local/bin/start.sh
RUN dos2unix /usr/local/bin/start.sh || true && chmod +x /usr/local/bin/start.sh

# Tout le mutable vit sur /workspace (monte ton Network Volume ici)
VOLUME ["/workspace"]

# Ports exposés : ComfyUI + JupyterLab
EXPOSE 8188 8888

# Pas de HEALTHCHECK (évite les restarts pendant installs/compil)
ENTRYPOINT ["/usr/local/bin/start.sh"]
