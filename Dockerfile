# Dockerfile
FROM nvidia/cuda:12.6.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/workspace/ComfyUI
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-dev python3-pip \
    git wget curl build-essential \
    ffmpeg libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    libgomp1 libgoogle-perftools-dev \
    tmux screen htop nvtop \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Alias Python et création du venv
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# Création et activation du virtual environment
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"
ENV VIRTUAL_ENV="/venv"

# Installation PyTorch avec CUDA 12.6 dans le venv
RUN pip install --upgrade pip && \
    pip install torch==2.5.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Installation ComfyUI
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR ${COMFYUI_PATH}
RUN pip install -r requirements.txt

# Installation des custom nodes essentiels
RUN cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git

# Installation des dépendances des custom nodes
RUN cd custom_nodes && \
    for dir in */; do \
        if [ -f "$dir/requirements.txt" ]; then \
            pip install -r "$dir/requirements.txt" || true; \
        fi; \
        if [ -f "$dir/install.py" ]; then \
            cd "$dir" && python install.py && cd ..; \
        fi; \
    done

# Création des dossiers nécessaires
RUN mkdir -p models/text_encoders models/vae models/unet models/loras \
    models/upscale_models input output temp

# Copie des scripts et handler
COPY scripts/ /workspace/scripts/
COPY configs/ /workspace/configs/
COPY workflows/ ${COMFYUI_PATH}/workflows/
COPY rp_handler.py /workspace/
COPY requirements.txt /workspace/
RUN chmod +x /workspace/scripts/*.sh

# Installation des dépendances RunPod
RUN pip install -r /workspace/requirements.txt

# Configuration des variables d'environnement optimales
ENV PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512"
ENV CUDA_MODULE_LOADING=LAZY
ENV TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0;10.0"
ENV TCMALLOC_LARGE_ALLOC_REPORT_THRESHOLD=10737418240
ENV SAGE_ATTENTION_IMPL=triton
ENV SAGE_ATTENTION_AUTOTUNE=1

EXPOSE 8188

WORKDIR /workspace

# Point d'entrée pour RunPod serverless
CMD ["python", "rp_handler.py"]