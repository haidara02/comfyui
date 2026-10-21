#!/bin/bash

COMFY_ROOT="/workspace/ComfyUI"
CUSTOM_NODES="${COMFY_ROOT}/custom_nodes"
LOG="/workspace/download.log"
R2_BUCKET="${R2_BUCKET:-comfyui-models}"

# ── Auth check ────────────────────────────────────────────────────────────────

# Strip stray whitespace/quotes that often sneak in when pasting into Vast env vars
HF_TOKEN="$(printf '%s' "$HF_TOKEN" | tr -d "[:space:]\"'")"

if [ -n "$HF_TOKEN" ]; then
    # An invalid token makes HF return 401 even for public repos, so verify it first
    if wget -q -O /dev/null --header="Authorization: Bearer ${HF_TOKEN}" \
        "https://huggingface.co/api/whoami-v2"; then
        echo "[AUTH] HuggingFace token valid — using authenticated downloads"
    else
        echo "[AUTH] HuggingFace token INVALID (401) — falling back to anonymous downloads"
        echo "       Regenerate it at https://huggingface.co/settings/tokens and update HF_TOKEN in Vast"
        HF_TOKEN=""
    fi
else
    echo "[AUTH] No HF_TOKEN set — downloading anonymously (may be slower)"
fi

# ── Helper ────────────────────────────────────────────────────────────────────

install_rclone() {
    command -v rclone >/dev/null && return 0

    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) echo "[R2] Unsupported architecture $(uname -m)"; return 1 ;;
    esac

    echo "[R2] Installing rclone..."
    local tmp
    tmp="$(mktemp -d)"
    wget -q -O "${tmp}/rclone.zip" "https://downloads.rclone.org/rclone-current-linux-${arch}.zip" \
        && python3 -m zipfile -e "${tmp}/rclone.zip" "${tmp}" \
        && install -m 755 "${tmp}"/rclone-*/rclone /usr/local/bin/rclone
    local status=$?
    rm -rf "$tmp"
    return $status
}

# Pull cached models from Cloudflare R2. The HF downloads below then skip whatever R2 supplied.
# Args are rclone --include filters, so each template only pulls the models it uses
# (the bucket is shared with the Flux template).
r2_pull() {
    if [ -z "$RCLONE_CONFIG_R2_ENDPOINT" ] || [ -z "$RCLONE_CONFIG_R2_ACCESS_KEY_ID" ]; then
        echo "[R2] No R2 credentials set — skipping cache, downloading from source"
        return
    fi

    install_rclone || { echo "[R2] rclone install failed — downloading from source"; return; }

    echo ""
    echo "[R2] Pulling models from r2:${R2_BUCKET}/models ..."
    rclone copy "r2:${R2_BUCKET}/models" "${COMFY_ROOT}/models" "$@" \
        --transfers 4 --multi-thread-streams 8 \
        --stats 30s --stats-one-line

    if [ $? -eq 0 ]; then
        echo "[R2] Pull complete"
    else
        echo "[R2] Pull failed — missing files will be downloaded from source"
    fi
}

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

# ── R2 model cache ────────────────────────────────────────────────────────────

echo "========================================"
echo " R2 model cache"
echo "========================================"

r2_pull \
    --include "/diffusion_models/z_image_turbo_bf16.safetensors" \
    --include "/text_encoders/qwen_3_4b.safetensors" \
    --include "/vae/ae.safetensors" \
    --include "/upscale_models/**" \
    --include "/RMBG/**"

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
    "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth" \
    "${COMFY_ROOT}/models/upscale_models" \
    "RealESRGAN_x4plus_anime_6B.pth" \
    "18 MB"

download \
    "https://huggingface.co/Kim2091/UltraSharpV2/resolve/main/4x-UltraSharpV2.safetensors" \
    "${COMFY_ROOT}/models/upscale_models" \
    "4x-UltraSharpV2.safetensors" \
    "133 MB"

# ── Background removal model ──────────────────────────────────────────────────
# Same files ComfyUI-RMBG would fetch on first use; pre-downloading lets R2 cache them

echo ""
echo "========================================"
echo " Background removal model (BiRefNet-HR-matting)"
echo "========================================"

BIREFNET_DIR="${COMFY_ROOT}/models/RMBG/BiRefNet"
for f in BiRefNet-HR-matting.safetensors birefnet.py BiRefNet_config.py config.json; do
    download \
        "https://huggingface.co/1038lab/BiRefNet/resolve/main/${f}" \
        "$BIREFNET_DIR" \
        "$f" \
        "$([ "$f" = "BiRefNet-HR-matting.safetensors" ] && echo "445 MB" || echo "<1 MB")"
done

# ── Custom nodes ──────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo " Custom node installation"
echo "========================================"

install_custom_node \
    "https://github.com/Fannovel16/comfyui_controlnet_aux" \
    "comfyui_controlnet_aux"

# Background removal (BiRefNet); models auto-download to models/RMBG on first use
# unless already pulled from R2
install_custom_node \
    "https://github.com/1038lab/ComfyUI-RMBG" \
    "ComfyUI-RMBG"

# Folder batch loading (Load Image List From Dir)
install_custom_node \
    "https://github.com/ltdrdata/ComfyUI-Inspire-Pack" \
    "ComfyUI-Inspire-Pack"

# Raster → SVG (vtracer); muted in the workflows but needed for them to load cleanly
install_custom_node \
    "https://github.com/Yanick112/ComfyUI-ToSVG" \
    "ComfyUI-ToSVG"

echo ""
echo "========================================"
echo " All done — restart ComfyUI to pick up"
echo " new models and nodes."
echo "========================================"
