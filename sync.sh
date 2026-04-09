#!/bin/bash
set -euo pipefail

IMAGES_FILE="images.txt"

if [ ! -f "$IMAGES_FILE" ]; then
    echo "Error: $IMAGES_FILE not found! Please create it with a list of images to sync."
    exit 1
fi

if [ -z "${ACR_REGISTRY:-}" ] || [ -z "${ACR_NAMESPACE:-}" ]; then
    echo "Error: ACR_REGISTRY or ACR_NAMESPACE is not set in environment variables."
    exit 1
fi

echo "Starting Docker image synchronization to ACR..."
echo "Target Registry: ${ACR_REGISTRY}"
echo "Target Namespace: ${ACR_NAMESPACE}"
echo "-----------------------------------"

while IFS= read -r image; do
    if [[ -z "$image" || "$image" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    echo "--- Processing image: ${image} ---"

    # 分割仓库名和标签
    if [[ "$image" == *:* ]]; then
        original_repo="${image%:*}"
        original_tag="${image#*:}"
    else
        original_repo="$image"
        original_tag="latest"
    fi

    # ---------- 归一化处理 ----------
    # 1. 去掉第一个斜杠前的 registry 地址（如 docker.io/、gcr.io/、quay.io/）
    # 2. 将剩余的斜杠替换为短横线（避免 ACR 多级路径拒绝推送）
    # 3. 对于 Docker Hub 官方镜像，去掉可选的 library/ 前缀
    normalized_repo=$(echo "$original_repo" | sed -E 's|^[^/]+/||' | sed 's|/|-|g')
    normalized_repo=$(echo "$normalized_repo" | sed 's/^library-//')
    # 如果归一化后为空（极端情况），则回退到原始仓库名（但几乎不会发生）
    if [ -z "$normalized_repo" ]; then
        normalized_repo="$original_repo"
    fi

    target_full_image_path="${ACR_REGISTRY}/${ACR_NAMESPACE}/${normalized_repo}:${original_tag}"

    echo "Original image:      ${image}"
    echo "Normalized repo:     ${normalized_repo}"
    echo "Target ACR image:    ${target_full_image_path}"

    # 检查目标镜像是否已存在
    if docker manifest inspect "${target_full_image_path}" > /dev/null 2>&1; then
        echo "Image ${target_full_image_path} already exists in ACR, skipping sync."
        echo "-----------------------------------"
        continue
    fi

    echo "Image not found in ACR, proceeding with sync..."

    docker pull --platform linux/arm64 "${image}"
    docker tag "${image}" "${target_full_image_path}"
    docker push "${target_full_image_path}"

    echo "Cleaning up local images..."
    docker rmi "${image}" || true
    docker rmi "${target_full_image_path}" || true

    echo "Successfully synced: ${image} -> ${target_full_image_path}"
    echo "-----------------------------------"
done < "$IMAGES_FILE"

echo "All specified images processed successfully."
echo "Synchronization process finished."
