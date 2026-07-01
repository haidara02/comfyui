#!/bin/bash

COMFY_ROOT="/workspace/ComfyUI"
CUSTOM_NODES="${COMFY_ROOT}/custom_nodes"

# ── Setup hf_transfer ─────────────────────────────────────────────────────────

echo "========================================"
echo " Setting up hf_transfer"
echo "========================================"

/venv/main/bin/python -m uv pip install hf-transfer huggingface_hub --quiet
export HF_HUB_ENABLE_HF_TRANSFER=1

# Use HF token if set in env (add HF_TOKEN to your template env vars for auth)
if [ -n "$HF_TOKEN" ]; then
    echo "[AUTH] Using HuggingFace token"
    export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
else
    echo "[AUTH] No HF_TOKEN set — downloading anonymously"
fi

# ── Helper ────────────────────────────────────────────────────────────────────

hf_download() {
    local repo="$1"
    local filepath="$2"
    local dest_dir="$3"
    local filename="$4"
    local size="$5"
    local out="${dest_dir}/${filename}"

    mkdir -p "$dest_dir"

    if [ -f "$out" ]; then
        echo "[SKIP] Already exists: $out"
        return
    fi

    echo ""
    echo "[DOWNLOADING] ${filename} (${size})"
    echo "  repo: ${repo}"
    echo "  → ${out}"

    /venv/main/bin/python -c "
from huggingface_hub import hf_hub_download
import shutil, os
path = hf_hub_download(
    repo_id='${repo}',
    filename='${filepath}',
    local_dir='/tmp/hf_cache',
)
os.makedirs('${dest_dir}', exist_ok=True)
shutil.move(path, '${out}')
print('[DONE] ${filename}')
"
    if [ $? -ne 0 ]; then
        echo "[FAILED] ${filename}"
        rm -f "$out"
    fi
}

# Fallback wget for non-HF URLs
wget_download() {
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

    wget -c \
        --progress=dot:giga \
        --output-file=/dev/stderr \
        -O "$out" \
        "$url" 2>&1

    if [ $? -eq 0 ]; then
        echo "[DONE] ${filename}"
    else
        echo "[FAILED] ${filename} — removing partial file"
        rm -f "$out"
    fi
}

install_custom_node() {
    local repo_url="$1"
    local node_dir="$2"

    if [ -d "${CUSTOM_NODES}/${node_dir}" ]; then
        echo "[SKIP] Custom node already installed: ${node_dir}"
        return
    fi

    echo ""
    echo "[INSTALLING NODE] ${node_dir}"
    git clone --depth=1 "$repo_url" "${CUSTOM_NODES}/${node_dir}"

    if [ -f "${CUSTOM_NODES}/${node_dir}/requirements.txt" ]; then
        echo "  Installing pip requirements..."
        /venv/main/bin/python -m uv pip install \
            -r "${CUSTOM_NODES}/${node_dir}/requirements.txt" \
            --quiet
    fi

    echo "[DONE] ${node_dir}"
}

patch_flux2fun() {
    local patch_file="${CUSTOM_NODES}/comfyui-flux2fun-controlnet/flux_patch.py"

    if [ ! -f "$patch_file" ]; then
        echo "[SKIP] flux_patch.py not found, skipping patch"
        return
    fi

    if grep -q "timestep_zero_index=None" "$patch_file"; then
        echo "[SKIP] flux_patch.py already patched"
        return
    fi

    echo "[PATCHING] Adding timestep_zero_index=None to patched_forward_orig..."
    sed -i 's/transformer_options={},/timestep_zero_index=None,\n        transformer_options={},/' "$patch_file"

    if grep -q "timestep_zero_index=None" "$patch_file"; then
        echo "[DONE] flux_patch.py patched successfully"
    else
        echo "[FAILED] Patch did not apply — check flux_patch.py manually"
    fi
}

# ── Models ────────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo " Flux 2 Dev model downloads (hf_transfer)"
echo "========================================"

hf_download \
    "Comfy-Org/flux2-dev" \
    "split_files/diffusion_models/flux2_dev_fp8mixed.safetensors" \
    "${COMFY_ROOT}/models/diffusion_models" \
    "flux2_dev_fp8mixed.safetensors" \
    "33 GB"

hf_download \
    "Comfy-Org/flux2-dev" \
    "split_files/loras/Flux2TurboComfyv2.safetensors" \
    "${COMFY_ROOT}/models/loras" \
    "Flux2TurboComfyv2.safetensors" \
    "2.57 GB"

hf_download \
    "Comfy-Org/flux2-dev" \
    "split_files/text_encoders/mistral_3_small_flux2_fp8.safetensors" \
    "${COMFY_ROOT}/models/text_encoders" \
    "mistral_3_small_flux2_fp8.safetensors" \
    "16.8 GB"

hf_download \
    "Comfy-Org/flux2-dev" \
    "split_files/vae/flux2-vae.safetensors" \
    "${COMFY_ROOT}/models/vae" \
    "flux2-vae.safetensors" \
    "320 MB"

# Alibaba repo — use wget as fallback since it may not support hf_transfer well
wget_download \
    "https://huggingface.co/alibaba-pai/FLUX.2-dev-Fun-Controlnet-Union/resolve/main/FLUX.2-dev-Fun-Controlnet-Union-2602.safetensors" \
    "${COMFY_ROOT}/models/controlnet" \
    "FLUX.2-dev-Fun-Controlnet-Union-2602.safetensors" \
    "~3.6 GB"

# ── Custom nodes ──────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo " Custom node installation"
echo "========================================"

install_custom_node \
    "https://github.com/Fannovel16/comfyui_controlnet_aux" \
    "comfyui_controlnet_aux"

install_custom_node \
    "https://github.com/bryanmcguire/comfyui-flux2fun-controlnet" \
    "comfyui-flux2fun-controlnet"

# ── Patch ─────────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo " Applying patches"
echo "========================================"

patch_flux2fun

echo ""
echo "========================================"
echo " All done — restart ComfyUI to pick up"
echo " new models, nodes, and patches."
echo "========================================"
