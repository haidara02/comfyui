#!/bin/bash

# === CONFIG — adjust if your ComfyUI lives elsewhere ===
COMFY_ROOT="/workspace/ComfyUI"

# Uncomment and paste your token if the HF repo requires auth:
# export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxx"

HF_HEADERS=""
if [ -n "$HF_TOKEN" ]; then
    HF_HEADERS="--header=Authorization: Bearer ${HF_TOKEN}"
fi

download() {
    local url="$1"
    local dest_dir="$2"
    local filename="$3"
    local size="$4"
    local out="${dest_dir}/${filename}"

    mkdir -p "$dest_dir"

    if [ -f "$out" ]; then
        echo "[SKIP] Already exists: $out"
        return
    fi

    echo ""
    echo "[DOWNLOADING] ${filename} (${size})"
    echo "  → ${out}"

    wget -c --progress=bar:force \
        ${HF_HEADERS:+"$HF_HEADERS"} \
        -O "$out" \
        "$url"

    if [ $? -eq 0 ]; then
        echo "[DONE] ${filename}"
    else
        echo "[FAILED] ${filename} — removing partial file"
        rm -f "$out"
    fi
}

echo "ComfyUI root: ${COMFY_ROOT}"
echo "Downloading 5 models..."

download \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors" \
    "${COMFY_ROOT}/models/diffusion_models" \
    "flux2_dev_fp8mixed.safetensors" \
    "33 GB"

download \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/loras/Flux2TurboComfyv2.safetensors" \
    "${COMFY_ROOT}/models/loras" \
    "Flux2TurboComfyv2.safetensors" \
    "2.57 GB"

download \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/mistral_3_small_flux2_fp8.safetensors" \
    "${COMFY_ROOT}/models/text_encoders" \
    "mistral_3_small_flux2_fp8.safetensors" \
    "16.8 GB"

download \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
    "${COMFY_ROOT}/models/vae" \
    "flux2-vae.safetensors" \
    "320 MB"

download \
    "https://huggingface.co/alibaba-pai/FLUX.2-dev-Fun-Controlnet-Union/resolve/main/FLUX.2-dev-Fun-Controlnet-Union-2602.safetensors" \
    "${COMFY_ROOT}/models/controlnet" \
    "FLUX.2-dev-Fun-Controlnet-Union-2602.safetensors" \
    "~unknown"

echo ""
echo "All done. Refresh ComfyUI to pick up the new models."
