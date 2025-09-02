#!/bin/bash
# scripts/health_check.sh

COMFYUI_PATH="/workspace/ComfyUI"
MODELS_DIR="$COMFYUI_PATH/models"
ERRORS=0

echo "Vérification de l'installation..."

# Vérifier les modèles essentiels
REQUIRED_MODELS=(
    "vae/wan_2.1_vae.safetensors"
    "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
    "loras/Wan2.2-I2V-A14B-4step-lora-rank64-Seko-V1-high-noise.safetensors"
    "loras/Wan2.2-I2V-A14B-4step-lora-rank64-Seko-V1-low-noise.safetensors"
)

for model in "${REQUIRED_MODELS[@]}"; do
    if [ -f "$MODELS_DIR/$model" ]; then
        echo "✅ $model"
    else
        echo "❌ Manquant: $model"
        ERRORS=$((ERRORS + 1))
    fi
done

# Vérifier au moins un modèle GGUF
GGUF_COUNT=$(ls -1 "$MODELS_DIR/unet/"*.gguf 2>/dev/null | wc -l)
if [ $GGUF_COUNT -gt 0 ]; then
    echo "✅ Modèles GGUF: $GGUF_COUNT trouvés"
else
    echo "❌ Aucun modèle GGUF trouvé"
    ERRORS=$((ERRORS + 1))
fi

# Vérifier les custom nodes essentiels
REQUIRED_NODES=(
    "ComfyUI-Manager"
    "ComfyUI-KJNodes"
    "ComfyUI-GGUF"
    "ComfyUI-VideoHelperSuite"
)

for node in "${REQUIRED_NODES[@]}"; do
    if [ -d "$COMFYUI_PATH/custom_nodes/$node" ]; then
        echo "✅ $node"
    else
        echo "❌ Node manquant: $node"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo "✅ Tous les composants sont installés!"
else
    echo "⚠️  $ERRORS erreurs détectées"
    echo "Lancez /workspace/scripts/download_models.sh pour corriger"
fi

exit $ERRORS