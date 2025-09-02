# Dockerfile
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/workspace/ComfyUI
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-dev python3.11-venv python3-pip \
    git wget curl build-essential \
    ffmpeg libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    libgomp1 libgoogle-perftools-dev \
    tmux screen htop nvtop \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Alias Python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# Création du virtual environment avec python3.11-venv
RUN python3.11 -m venv /venv --system-site-packages
ENV PATH="/venv/bin:$PATH"
ENV VIRTUAL_ENV="/venv"

# Installation PyTorch nightly avec CUDA 12.8 pour RTX 5090 (sm_120)
RUN pip install --upgrade pip && \
    pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128

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
COPY handler.py /workspace/
COPY test_handler.py /workspace/
COPY requirements.txt /workspace/
RUN chmod +x /workspace/scripts/*.sh

# Installation des dépendances RunPod
RUN pip install -r /workspace/requirements.txt

# Test handler import at build time
RUN cd /workspace && python test_handler.py

# Configuration des variables d'environnement pour RTX 5090 et CUDA 12.8
ENV PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512,expandable_segments:True"
ENV CUDA_MODULE_LOADING=LAZY
ENV TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0;10.0"
ENV TCMALLOC_LARGE_ALLOC_REPORT_THRESHOLD=10737418240

# SageAttention 2+ configuration (may have issues with RTX 5090 sm_120)
ENV SAGE_ATTENTION_IMPL=triton
ENV SAGE_ATTENTION_AUTOTUNE=1
ENV SAGE_ATTENTION_VERSION=2

# RTX 5090 Blackwell support
ENV TORCH_ALLOW_TF32_CUBLAS_OVERRIDE=1
ENV CUDA_LAUNCH_BLOCKING=0

EXPOSE 8188

WORKDIR /workspace

# Skip ComfyUI test - causes issues in RunPod build environment
# RUN cd ${COMFYUI_PATH} && python main.py --quick-test-for-ci || echo "ComfyUI test completed"

# Point d'entrée pour RunPod serverless
CMD ["python", "-u", "/workspace/handler.py"]