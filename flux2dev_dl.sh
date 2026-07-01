#!/bin/bash

COMFY_ROOT="/workspace/ComfyUI"
CUSTOM_NODES="${COMFY_ROOT}/custom_nodes"
LOG="/workspace/download.log"

# ── Helper ────────────────────────────────────────────────────────────────────

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
        -O "$out" \
        "$url"

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

    # Check if already patched
    if grep -q "timestep_zero_index=None" "$patch_file"; then
        echo "[SKIP] flux_patch.py already patched"
        return
    fi

    echo "[PATCHING] Adding timestep_zero_index=None to patched_forward_orig..."

    # Replace the function signature — insert timestep_zero_index=None before transformer_options
    sed -i 's/transformer_options={},/timestep_zero_index=None,\n        transformer_options={},/' "$patch_file"

    if grep -q "timestep_zero_index=None" "$patch_file"; then
        echo "[DONE] flux_patch.py patched successfully"
    else
        echo "[FAILED] Patch did not apply — check flux_patch.py manually"
    fi
}

# ── Models ────────────────────────────────────────────────────────────────────

echo "========================================"
echo " Flux 2 Dev model downloads"
echo "========================================"

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
