#!/bin/bash
# scripts/switch_quant.sh

QUANT=$1
WORKFLOW_PATH="${2:-/workspace/ComfyUI/workflows/wan22_i2v_adaptive.json}"

if [ -z "$QUANT" ]; then
    echo "Usage: ./switch_quant.sh [Q4_K_S|Q5_K_S|Q6_K|Q8_0] [workflow_path]"
    echo ""
    echo "Quantizations disponibles:"
    ls -1 /workspace/ComfyUI/models/unet/*.gguf 2>/dev/null | xargs -n1 basename | sed 's/.*_\(Q[0-9]_K_[SM]\|Q[0-9]_[0-9]\)\.gguf/\1/' | sort -u
    exit 1
fi

# Vérifier que les modèles existent
HIGH_MODEL="wan2.2_i2v_high_noise_14B_${QUANT}.gguf"
LOW_MODEL="wan2.2_i2v_low_noise_14B_${QUANT}.gguf"

if [ ! -f "/workspace/ComfyUI/models/unet/$HIGH_MODEL" ] || [ ! -f "/workspace/ComfyUI/models/unet/$LOW_MODEL" ]; then
    echo "❌ Modèles $QUANT non trouvés!"
    echo "Modèles disponibles:"
    ls -1 /workspace/ComfyUI/models/unet/*.gguf
    exit 1
fi

# Mise à jour du workflow
if [ -f "$WORKFLOW_PATH" ]; then
    # Backup
    cp "$WORKFLOW_PATH" "${WORKFLOW_PATH}.backup"
    
    # Remplacer les références aux modèles
    sed -i "s/wan2\.2_i2v_high_noise_14B_Q[0-9]_K_[SM]\.gguf/${HIGH_MODEL}/g" "$WORKFLOW_PATH"
    sed -i "s/wan2\.2_i2v_low_noise_14B_Q[0-9]_K_[SM]\.gguf/${LOW_MODEL}/g" "$WORKFLOW_PATH"
    sed -i "s/wan2\.2_i2v_high_noise_14B_Q[0-9]_[0-9]\.gguf/${HIGH_MODEL}/g" "$WORKFLOW_PATH"
    sed -i "s/wan2\.2_i2v_low_noise_14B_Q[0-9]_[0-9]\.gguf/${LOW_MODEL}/g" "$WORKFLOW_PATH"
    
    echo "✅ Workflow mis à jour pour utiliser $QUANT"
else
    echo "⚠️  Workflow non trouvé: $WORKFLOW_PATH"
fi

# Mettre à jour la variable d'environnement
export DEFAULT_QUANT=$QUANT
echo "✅ Quantization changée vers $QUANT"