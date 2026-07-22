#!/bin/bash

COMFY_ROOT="/workspace/ComfyUI"
CUSTOM_NODES="${COMFY_ROOT}/custom_nodes"
LOG="/workspace/download.log"

# ── Auth check ────────────────────────────────────────────────────────────────

if [ -n "$HF_TOKEN" ]; then
    echo "[AUTH] HuggingFace token found — using authenticated downloads"
else
    echo "[AUTH] No HF_TOKEN set — downloading anonymously (may be slower)"
fi

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

    local auth_header=""
    if [ -n "$HF_TOKEN" ]; then
        auth_header="--header=Authorization: Bearer ${HF_TOKEN}"
    fi

    wget -c --progress=bar:force \
        ${auth_header:+"$auth_header"} \
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
    local nodes_file="${CUSTOM_NODES}/comfyui-flux2fun-controlnet/nodes.py"

    # ── Patch 1: timestep_zero_index in flux_patch.py ─────────────────────────
    if [ ! -f "$patch_file" ]; then
        echo "[SKIP] flux_patch.py not found, skipping patch 1"
    elif grep -q "timestep_zero_index=None" "$patch_file"; then
        echo "[SKIP] flux_patch.py already patched (timestep_zero_index)"
    else
        echo "[PATCHING] Adding timestep_zero_index=None to patched_forward_orig..."
        sed -i 's/transformer_options={},/timestep_zero_index=None,\n        transformer_options={},/' "$patch_file"

        if grep -q "timestep_zero_index=None" "$patch_file"; then
            echo "[DONE] flux_patch.py patched successfully"
        else
            echo "[FAILED] flux_patch.py patch did not apply — check manually"
        fi
    fi

    # ── Patch 2: multigpu_clones in nodes.py ──────────────────────────────────
    if [ ! -f "$nodes_file" ]; then
        echo "[SKIP] nodes.py not found, skipping patch 2"
    elif grep -q "multigpu_clones" "$nodes_file"; then
        echo "[SKIP] nodes.py already patched (multigpu_clones)"
    else
        echo "[PATCHING] Adding multigpu_clones to ControlNetWrapper..."
        sed -i 's/class ControlNetWrapper:/class ControlNetWrapper:\n    multigpu_clones = {}/' "$nodes_file"

        if grep -q "multigpu_clones" "$nodes_file"; then
            echo "[DONE] nodes.py patched successfully"
        else
            echo "[FAILED] nodes.py patch did not apply — check manually"
        fi
    fi
}

# ── Flux 2 Dev models ─────────────────────────────────────────────────────────

echo "========================================"
echo " Flux 2 Dev model downloads"
echo "========================================"

download \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors" \
    "${COMFY_ROOT}/models/diffusion_models" \
    "flux2_dev_fp8mixed.safetensors" \
    "33 GB"

download \
    "https://huggingface.co/ByteZSzn/Flux.2-Turbo-ComfyUI/resolve/main/Flux_2-Turbo-LoRA_comfyui.safetensors" \
    "${COMFY_ROOT}/models/loras" \
    "Flux_2-Turbo-LoRA_comfyui.safetensors" \
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

# ── Z Image Turbo models ──────────────────────────────────────────────────────

echo ""
echo "========================================"
echo " Z Image Turbo model downloads"
echo "========================================"

download \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" \
    "${COMFY_ROOT}/models/diffusion_models" \
    "z_image_turbo_bf16.safetensors" \
    "11.5 GB"

download \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
    "${COMFY_ROOT}/models/text_encoders" \
    "qwen_3_4b.safetensors" \
    "7.5 GB"

download \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" \
    "${COMFY_ROOT}/models/vae" \
    "ae.safetensors" \
    "320 MB"

# ── Upscale models ────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo " Upscale model downloads"
echo "========================================"

download \
    "https://github.com/Derpiesaurus/models/releases/download/v2.0_HQ/2x_StarSample_V2.0_HQ.safetensors" \
    "${COMFY_ROOT}/models/upscale_models" \
    "2x_StarSample_V2.0_HQ.safetensors" \
    "157 MB"

download \
    "https://huggingface.co/Comfy-Org/Real-ESRGAN_repackaged/resolve/main/RealESRGAN_x4plus.safetensors" \
    "${COMFY_ROOT}/models/upscale_models" \
    "RealESRGAN_x4plus.safetensors" \
    "64 MB"

download \
    "https://huggingface.co/Kim2091/UltraSharpV2/resolve/main/4x-UltraSharpV2.safetensors" \
    "${COMFY_ROOT}/models/upscale_models" \
    "4x-UltraSharpV2.safetensors" \
    "133 MB"

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
