#!/bin/bash
# One-off: upload this instance's models to the R2 cache.
# Run from the Jupyter terminal with the read-write (upload) token; delete that token afterwards.
#   bash r2_upload.sh            dry run (lists what would upload)
#   bash r2_upload.sh --go       upload

COMFY_ROOT="/workspace/ComfyUI"
R2_BUCKET="${R2_BUCKET:-comfyui-models}"

if ! command -v rclone >/dev/null; then
    echo "rclone not found — it's installed by the provisioning script when R2 credentials are set."
    echo "Install manually: curl -fsSL https://rclone.org/install.sh | bash"
    exit 1
fi

export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true   # bucket-scoped tokens can't list/create buckets

# Reuse the endpoint from the Vast env vars if present; always ask for the upload keys
if [ -z "$RCLONE_CONFIG_R2_ENDPOINT" ]; then
    read -r -p "R2 endpoint (https://<ACCOUNT_ID>.r2.cloudflarestorage.com): " RCLONE_CONFIG_R2_ENDPOINT
    export RCLONE_CONFIG_R2_ENDPOINT
fi
read -r  -p "Upload token access key ID: " RCLONE_CONFIG_R2_ACCESS_KEY_ID
read -rs -p "Upload token secret: " RCLONE_CONFIG_R2_SECRET_ACCESS_KEY; echo
export RCLONE_CONFIG_R2_ACCESS_KEY_ID RCLONE_CONFIG_R2_SECRET_ACCESS_KEY

# Model weights plus the BiRefNet folder (its .py/config files are needed alongside the weights)
FILTERS=(--include "*.safetensors" --include "*.pth" --include "/RMBG/**")

if [ "$1" = "--go" ]; then
    rclone copy "${COMFY_ROOT}/models" "r2:${R2_BUCKET}/models" "${FILTERS[@]}" \
        --transfers 4 --s3-chunk-size 128M --s3-upload-concurrency 8 -P
else
    rclone copy "${COMFY_ROOT}/models" "r2:${R2_BUCKET}/models" "${FILTERS[@]}" --dry-run
    echo ""
    echo "Dry run only. Re-run with --go to upload."
fi
