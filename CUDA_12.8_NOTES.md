# 🚨 CUDA 12.8 + RTX 5090 Configuration Notes

## ⚠️ Important Compatibility Warnings

### RTX 5090 (Blackwell Architecture)
- **Compute Capability**: sm_120 (nouveau)
- **Problème**: PyTorch stable ne supporte pas encore sm_120
- **Solution**: PyTorch nightly builds avec CUDA 12.8

### SageAttention 2+ Status
- **État actuel**: Problèmes connus avec RTX 5090
- **Symptômes**: Échecs silencieux ou erreurs CUDA
- **Recommandation**: Définir `SAGE_ATTENTION_IMPL=auto` pour fallback

## 🔧 Configuration Appliquée

### Docker Base
```dockerfile
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04
```

### PyTorch Installation
```dockerfile
pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
```

### Variables d'Environnement RTX 5090
```bash
PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512,expandable_segments:True"
TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0;10.0"
TORCH_ALLOW_TF32_CUBLAS_OVERRIDE=1
SAGE_ATTENTION_IMPL=auto  # Fallback si erreur
```

## 🎯 Performance Attendue

### RTX 5090 vs RTX 4090
- **Sans optimisations**: 2x plus lent (25min vs 14min)
- **Avec PyTorch nightly**: Performance normale attendue
- **SageAttention**: Peut ne pas fonctionner (fallback automatique)

## 🛠️ Dépannage

### Erreur "sm_120 not compatible"
```bash
# Vérifier PyTorch version
python -c "import torch; print(torch.__version__)"
# Doit afficher version nightly (ex: 2.8.0.dev20250102+cu128)
```

### SageAttention Échec
```bash
# Variables de debug
export CUDA_LAUNCH_BLOCKING=1
export SAGE_ATTENTION_IMPL=auto
```

### Fallback Options
Si problèmes persistent :
1. Désactiver SageAttention : `SAGE_ATTENTION_IMPL=disabled`
2. Utiliser FlashAttention : `USE_FLASH_ATTENTION=true`
3. Mode compatibilité : `PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:256"`

## 📈 Monitoring

### Vérifications Démarrage
- PyTorch detect RTX 5090 : `torch.cuda.get_device_name(0)`
- CUDA version : `torch.version.cuda`
- Compute capability : `torch.cuda.get_device_capability(0)`

**Status**: Configuration expérimentale pour early adopters RTX 5090