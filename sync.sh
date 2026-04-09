#!/bin/bash
set -euo pipefail  # -e: 命令失败立即退出; -u: 未定义变量报错; -o pipefail: 管道中任何命令失败则整体失败

IMAGES_FILE="images.txt"

# 检查镜像列表文件是否存在
if [ ! -f "$IMAGES_FILE" ]; then
    echo "Error: $IMAGES_FILE not found! Please create it with a list of images to sync."
    exit 1
fi

# 检查必需的环境变量是否已设置
if [ -z "${ACR_REGISTRY:-}" ] || [ -z "${ACR_NAMESPACE:-}" ]; then
    echo "Error: ACR_REGISTRY or ACR_NAMESPACE is not set in environment variables."
    echo "Please ensure they are provided (e.g., via GitHub Actions secrets)."
    exit 1
fi

echo "Starting Docker image synchronization to ACR..."
echo "Target Registry: ${ACR_REGISTRY}"
echo "Target Namespace: ${ACR_NAMESPACE}"
echo "-----------------------------------"

# 逐行读取镜像列表
while IFS= read -r image; do
    # 跳过空行和注释行（以 # 开头）
    if [[ -z "$image" || "$image" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    echo "--- Processing image: ${image} ---"

    # 分割仓库名和标签（如果未指定标签，默认使用 latest）
    if [[ "$image" == *:* ]]; then
        original_repo="${image%:*}"
        original_tag="${image#*:}"
    else
        original_repo="$image"
        original_tag="latest"
    fi

    # 构造目标 ACR 镜像完整路径
    target_full_image_path="${ACR_REGISTRY}/${ACR_NAMESPACE}/${original_repo}:${original_tag}"

    echo "Original image:      ${image}"
    echo "Target ACR image:    ${target_full_image_path}"

    # 检查目标镜像是否已存在于 ACR
    if docker manifest inspect "${target_full_image_path}" > /dev/null 2>&1; then
        echo "Image ${target_full_image_path} already exists in ACR, skipping sync."
        echo "-----------------------------------"
        continue
    fi

    echo "Image not found in ACR, proceeding with sync..."

    # 拉取原始镜像
    echo "Pulling ${image} ..."
    docker pull "${image}"

    # 重新打标签
    echo "Tagging ${image} -> ${target_full_image_path}"
    docker tag "${image}" "${target_full_image_path}"

    # 推送到 ACR
    echo "Pushing ${target_full_image_path} ..."
    docker push "${target_full_image_path}"

    # 清理本地镜像，释放 Runner 磁盘空间
    echo "Cleaning up local images..."
    docker rmi "${image}" || true
    docker rmi "${target_full_image_path}" || true

    echo "Successfully synced: ${image} -> ${target_full_image_path}"
    echo "-----------------------------------"
done < "$IMAGES_FILE"

echo "All specified images processed successfully."
echo "Synchronization process finished."
