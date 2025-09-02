#!/bin/bash
# scripts/start.sh

echo "========================================="
echo "   Wan 2.2 I2V ComfyUI - RunPod Setup"
echo "========================================="

# Source environment setup
source /workspace/configs/env_setup.sh

# Detect GPU and configure
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
GPU_ARCH=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1)

echo "GPU détectée: $GPU_NAME"
echo "VRAM: ${VRAM}MB"
echo "Architecture: $GPU_ARCH"

# Auto-select quantization based on VRAM
if [ $VRAM -lt 24000 ]; then
    export DEFAULT_QUANT="Q4_K_S"
    echo "Mode: Prototype (Q4_K_S)"
elif [ $VRAM -lt 32000 ]; then
    export DEFAULT_QUANT="Q5_K_S"
    echo "Mode: Standard (Q5_K_S)"
elif [ $VRAM -lt 48000 ]; then
    export DEFAULT_QUANT="Q6_K"
    echo "Mode: Qualité (Q6_K)"
else
    export DEFAULT_QUANT="Q8_0"
    echo "Mode: Maximum (Q8_0)"
fi

# Setup network disk if available
if [ -d "/network-disk" ]; then
    echo "Configuration du network disk..."
    /workspace/scripts/setup_network_disk.sh
fi

# Health check
echo "Vérification des modèles..."
/workspace/scripts/health_check.sh

# Download models if needed
if [ ! -f "${COMFYUI_PATH}/models/vae/wan_2.1_vae.safetensors" ]; then
    echo "Téléchargement des modèles de base..."
    /workspace/scripts/download_models.sh
fi

# Start ComfyUI
echo "Démarrage de ComfyUI..."
cd ${COMFYUI_PATH}
python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header