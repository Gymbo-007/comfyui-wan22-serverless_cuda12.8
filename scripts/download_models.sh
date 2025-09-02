#!/bin/bash
# scripts/download_models.sh

MODELS_DIR="${COMFYUI_PATH}/models"
VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)

echo "Téléchargement des modèles Wan 2.2..."

# Text Encoder (toujours nécessaire)
if [ ! -f "$MODELS_DIR/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" ]; then
    echo "Téléchargement UMT5 XXL..."
    wget -c "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
        -P "$MODELS_DIR/text_encoders/"
fi

# VAE (toujours nécessaire)
if [ ! -f "$MODELS_DIR/vae/wan_2.1_vae.safetensors" ]; then
    echo "Téléchargement VAE..."
    wget -c "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
        -P "$MODELS_DIR/vae/"
fi

# LoRAs de base Seko
echo "Téléchargement LoRAs Seko..."
wget -nc "https://huggingface.co/Seko/Wan2.2-I2V-4step-lora/resolve/main/Wan2.2-I2V-A14B-4step-lora-rank64-Seko-V1-high-noise.safetensors" \
    -P "$MODELS_DIR/loras/" 2>/dev/null || true
wget -nc "https://huggingface.co/Seko/Wan2.2-I2V-4step-lora/resolve/main/Wan2.2-I2V-A14B-4step-lora-rank64-Seko-V1-low-noise.safetensors" \
    -P "$MODELS_DIR/loras/" 2>/dev/null || true

# GGUF Models selon VRAM
echo "Téléchargement modèles GGUF selon VRAM disponible..."

# Q4_K_S pour tous (prototype)
wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_high_noise_14B_Q4_K_S.gguf" \
    -P "$MODELS_DIR/unet/" 2>/dev/null || true
wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_low_noise_14B_Q4_K_S.gguf" \
    -P "$MODELS_DIR/unet/" 2>/dev/null || true

# Q5_K_S si VRAM >= 24GB
if [ $VRAM -ge 24000 ]; then
    wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_high_noise_14B_Q5_K_S.gguf" \
        -P "$MODELS_DIR/unet/" 2>/dev/null || true
    wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_low_noise_14B_Q5_K_S.gguf" \
        -P "$MODELS_DIR/unet/" 2>/dev/null || true
fi

# Q6_K si VRAM >= 32GB
if [ $VRAM -ge 32000 ]; then
    wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_high_noise_14B_Q6_K.gguf" \
        -P "$MODELS_DIR/unet/" 2>/dev/null || true
    wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_low_noise_14B_Q6_K.gguf" \
        -P "$MODELS_DIR/unet/" 2>/dev/null || true
fi

# Q8_0 si VRAM >= 48GB
if [ $VRAM -ge 48000 ]; then
    wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_high_noise_14B_Q8_0.gguf" \
        -P "$MODELS_DIR/unet/" 2>/dev/null || true
    wget -nc "https://huggingface.co/city96/wan-2.2-i2v-gguf/resolve/main/wan2.2_i2v_low_noise_14B_Q8_0.gguf" \
        -P "$MODELS_DIR/unet/" 2>/dev/null || true
fi

# Modèle upscale
echo "Téléchargement modèle upscale..."
wget -nc "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth" \
    -P "$MODELS_DIR/upscale_models/" 2>/dev/null || true

# RIFE pour frame interpolation
echo "Téléchargement RIFE..."
mkdir -p "${COMFYUI_PATH}/custom_nodes/ComfyUI-Frame-Interpolation/models"
wget -nc "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation/releases/download/models/rife49.pth" \
    -P "${COMFYUI_PATH}/custom_nodes/ComfyUI-Frame-Interpolation/models/" 2>/dev/null || true

echo "Téléchargement terminé!"