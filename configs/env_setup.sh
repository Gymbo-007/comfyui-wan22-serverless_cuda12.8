#!/bin/bash
# configs/env_setup.sh

# Optimisations PyTorch
export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512,expandable_segments:True"
export CUDA_MODULE_LOADING=LAZY
export TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0;10.0"

# Optimisations mémoire
export TCMALLOC_LARGE_ALLOC_REPORT_THRESHOLD=10737418240
export MALLOC_TRIM_THRESHOLD_=100000

# SageAttention 2.0+
export SAGE_ATTENTION_IMPL=triton
export SAGE_ATTENTION_AUTOTUNE=1

# TF32 pour Ada Lovelace et plus récent
export TORCH_ALLOW_TF32_CUBLAS_OVERRIDE=1

# Optimisations ComfyUI
export COMFYUI_DISABLE_SMART_MEMORY=0
export COMFYUI_FORCE_FP16=0

echo "Variables d'environnement configurées"