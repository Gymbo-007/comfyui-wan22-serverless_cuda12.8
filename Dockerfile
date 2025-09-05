FROM nvidia/cuda:12.8-devel-ubuntu22.04

# Variables d'environnement
ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=$CUDA_HOME/bin:$PATH

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev \
    git wget curl build-essential cmake ninja-build \
    ffmpeg libsm6 libxext6 libxrender-dev libglib2.0-0 \
    htop nvtop net-tools \
    && rm -rf /var/lib/apt/lists/*

# Installation PyTorch NIGHTLY avec CUDA 12.8
RUN pip3 install --pre torch==2.8.0.dev20250605+cu128 torchvision==0.23.0.dev20250605+cu128 torchaudio==2.8.0.dev20250605+cu128 --index-url https://download.pytorch.org/whl/nightly/cu128

# Installation JupyterLab
RUN pip3 install jupyterlab ipywidgets notebook jupyterlab-git

# Script de démarrage
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8888 3000

CMD ["/start.sh"]