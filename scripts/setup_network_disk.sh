#!/bin/bash
# scripts/setup_network_disk.sh

NETWORK_DISK="/network-disk"
COMFYUI_PATH="/workspace/ComfyUI"

if [ ! -d "$NETWORK_DISK" ]; then
    echo "Network disk non disponible"
    exit 0
fi

echo "Configuration du network disk..."

# Créer la structure si nécessaire
mkdir -p "$NETWORK_DISK/loras"
mkdir -p "$NETWORK_DISK/outputs"
mkdir -p "$NETWORK_DISK/inputs"
mkdir -p "$NETWORK_DISK/cache"
mkdir -p "$NETWORK_DISK/workflows"

# Symlinks pour les LoRAs personnalisés
if [ -d "$NETWORK_DISK/loras" ]; then
    echo "Lien des LoRAs personnalisés..."
    for lora in "$NETWORK_DISK/loras"/*.safetensors; do
        if [ -f "$lora" ]; then
            ln -sf "$lora" "$COMFYUI_PATH/models/loras/" 2>/dev/null
        fi
    done
fi

# Symlink pour les outputs
rm -rf "$COMFYUI_PATH/output"
ln -sf "$NETWORK_DISK/outputs" "$COMFYUI_PATH/output"

# Symlink pour les inputs
if [ -d "$NETWORK_DISK/inputs" ]; then
    for input in "$NETWORK_DISK/inputs"/*; do
        if [ -f "$input" ]; then
            ln -sf "$input" "$COMFYUI_PATH/input/" 2>/dev/null
        fi
    done
fi

# Symlink pour les workflows sauvegardés
if [ -d "$NETWORK_DISK/workflows" ]; then
    for workflow in "$NETWORK_DISK/workflows"/*.json; do
        if [ -f "$workflow" ]; then
            ln -sf "$workflow" "$COMFYUI_PATH/workflows/" 2>/dev/null
        fi
    done
fi

echo "Network disk configuré avec succès!"