# ComfyUI Wan 2.2 RunPod Template

Production-ready Docker template for ComfyUI Wan 2.2 Image-to-Video generation on RunPod serverless.

## 🚀 Fonctionnalités

- **Wan 2.2 I2V** : Dernière version du modèle image-to-video
- **Quantization adaptative** : Sélection automatique selon la VRAM (Q4_K_S à Q8_0)
- **RunPod Serverless** : Handler API intégré
- **Post-processing** : Upscaling + interpolation RIFE
- **Multi-GPU** : Support RTX 4090, 5090, A5000, 6000 Ada

## 📦 Structure

```
├── Dockerfile                 # Image Docker principal
├── docker-compose.yml         # Pour développement local
├── rp_handler.py             # Handler RunPod serverless
├── requirements.txt          # Dépendances Python
├── start_service.sh          # Démarrage adaptatif
├── scripts/
│   ├── start.sh              # Démarrage développement
│   ├── download_models.sh    # Téléchargement modèles
│   ├── health_check.sh       # Vérification installation
│   ├── setup_network_disk.sh # Configuration network storage
│   └── switch_quant.sh       # Changement quantization
├── configs/
│   ├── env_setup.sh          # Variables d'environnement
│   └── gpu_profiles.json     # Profils GPU optimisés
└── workflows/
    └── Wan22_I2V_Native_3_stage.json # Workflow ComfyUI
```

## 🛠️ Installation

### RunPod Serverless

1. **Créer l'image Docker** :
```bash
docker build -t wan22-runpod .
```

2. **Déployer sur RunPod** :
   - Pusher l'image sur Docker Hub/Registry
   - Créer une template RunPod serverless
   - Configurer l'endpoint

### Développement Local

```bash
# Cloner et builder
git clone <repo>
cd Wan2.2-runpod-template
docker-compose up --build

# Accès ComfyUI : http://localhost:8188
```

## 📡 API Usage

### Input Format
```json
{
  "input": {
    "image": "base64_encoded_image",
    "prompt": "high quality video, smooth motion",
    "negative_prompt": "static, blurry, low quality",
    "resolution": 832,
    "length": 25
  }
}
```

### Output Format
```json
{
  "videos": [
    {
      "filename": "output_video.mp4",
      "video_base64": "base64_encoded_video"
    }
  ],
  "prompt_id": "12345-abcde",
  "processing_time": 45.2
}
```

## ⚡ Optimisations

### GPU Profiles Automatiques
- **RTX 4090** (24GB) : Q5_K_S, résolution 832px
- **RTX 5090** (32GB) : Q6_K, résolution 1024px  
- **RTX 6000 Ada** (48GB) : Q8_0, résolution 1280px

### Variables d'Environnement
```bash
PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512"
SAGE_ATTENTION_IMPL=triton
SAGE_ATTENTION_AUTOTUNE=1
```

## 🎮 Workflow

1. **Stage 1** : High-noise model (étapes 0-2)
2. **Stage 2** : Low-noise model (étapes 2-4) 
3. **Stage 3** : Final model (étapes 4-8)
4. **Post-process** : Upscaling + RIFE interpolation

## 📋 Modèles Requis

### Automatique via download_models.sh
- `umt5_xxl_fp8_e4m3fn_scaled.safetensors` (Text Encoder)
- `wan_2.1_vae.safetensors` (VAE)
- `wan2.2_i2v_*_14B_QX.gguf` (Models GGUF)
- `Wan2.2-I2V-A14B-4step-lora-*.safetensors` (LoRAs)

## 🔧 Configuration

### Qualité/Performance
```bash
# Prototype (rapide)
Resolution: 208px, Steps: 6, Quant: Q4_K_S

# Standard 
Resolution: 832px, Steps: 6, Quant: Q5_K_S

# Haute qualité
Resolution: 1280px, Steps: 12, Quant: Q8_0
```

### Network Storage
Le template supporte le network disk RunPod pour :
- LoRAs personnalisés
- Cache des modèles
- Sauvegarde des outputs
- Workflows personnalisés

## 🐛 Debugging

```bash
# Logs ComfyUI
tail -f /tmp/comfyui.log

# Test handler
python test_handler.py

# Vérification sanité
/workspace/scripts/health_check.sh
```

## 📊 Performance

| GPU | VRAM | Resolution | Steps | Temps* |
|-----|------|------------|-------|--------|
| RTX 4090 | 24GB | 832px | 6 | ~30s |
| RTX 5090 | 32GB | 1024px | 8 | ~25s |
| RTX 6000 Ada | 48GB | 1280px | 12 | ~40s |

*Temps approximatifs pour 25 frames

## 📝 License

Template optimisé pour RunPod - Usage commercial autorisé