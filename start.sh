#!/bin/bash

# Vérifier que ComfyUI Portable est présent
if [ ! -d "/workspace/ComfyUI" ]; then
    echo "ERREUR: ComfyUI Portable non trouvé sur le network volume"
    exit 1
fi

# Démarrer JupyterLab
jupyter lab --allow-root --no-browser --port=8888 --ip=* &

# Démarrer ComfyUI Portable
cd /workspace/ComfyUI
python main.py --listen --port 3000 --cuda-device 0