# PyTorch 2.8 + CUDA 12.8 + cuDNN9 (DEVEL)
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

# Outils système + confort terminal
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates tzdata \
    python3-venv python3-dev build-essential \
    ffmpeg wget aria2 unzip dos2unix \
    bash-completion tmux htop ripgrep fd-find bat lsb-release \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && ln -sf /usr/bin/batcat /usr/local/bin/bat \
 && rm -rf /var/lib/apt/lists/*

# JupyterLab global
RUN pip install --no-cache-dir jupyterlab

# Workspace & start
RUN mkdir -p /workspace
COPY start.sh /usr/local/bin/start.sh
RUN dos2unix /usr/local/bin/start.sh || true && chmod +x /usr/local/bin/start.sh

# Shim service code
ENV SHIM_DIR=/opt/shim
COPY shim ${SHIM_DIR}

VOLUME ["/workspace"]
EXPOSE 8188 8888 8080

ENTRYPOINT ["/usr/local/bin/start.sh"]
