#!/bin/bash

# Git Post-Commit Hook: 自动同步路由配置到主仓库
# 使用方法：
# 1. 将此文件复制到微服务仓库的 .git/hooks/post-commit
# 2. 配置 INFRA_REPO_PATH 环境变量或在此脚本中设置
# 3. 配置 SERVICE_NAME 环境变量（如：user, order, feed）

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置：主仓库路径（uyou-api-gateway 仓库）
# 方式 1: 通过环境变量设置
INFRA_REPO_PATH="${INFRA_REPO_PATH:-}"

# 方式 2: 通过配置文件设置（在微服务仓库根目录创建 .infra-sync-config）
CONFIG_FILE=".infra-sync-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 服务名称（从当前仓库路径推断或手动设置）
SERVICE_NAME="${SERVICE_NAME:-$(basename "$(git rev-parse --show-toplevel)")}"
# 移除可能的后缀（如 user-service -> user）
SERVICE_NAME="${SERVICE_NAME%-service}"
SERVICE_NAME="${SERVICE_NAME#uyou-}"

# 路由文件路径
ROUTES_FILE="apisix/routes.yaml"

# 检查路由文件是否存在
if [ ! -f "$ROUTES_FILE" ]; then
    echo -e "${YELLOW}⚠ 路由文件不存在: ${ROUTES_FILE}${NC}"
    echo -e "${YELLOW}  跳过同步${NC}"
    exit 0
fi

# 检查路由文件是否在本次提交中
if ! git diff-tree --no-commit-id --name-only -r HEAD | grep -q "^${ROUTES_FILE}$"; then
    echo -e "${BLUE}ℹ 本次提交未修改 ${ROUTES_FILE}，跳过同步${NC}"
    exit 0
fi

# 检查主仓库路径
if [ -z "$INFRA_REPO_PATH" ]; then
    echo -e "${RED}❌ 错误: 未设置 INFRA_REPO_PATH${NC}"
    echo ""
    echo "请设置主仓库路径，方式："
    echo "  1. 环境变量: export INFRA_REPO_PATH=/path/to/uyou-api-gateway"
    echo "  2. 配置文件: 在仓库根目录创建 .infra-sync-config，内容："
    echo "     INFRA_REPO_PATH=/path/to/uyou-api-gateway"
    exit 1
fi

if [ ! -d "$INFRA_REPO_PATH" ]; then
    echo -e "${RED}❌ 错误: 主仓库路径不存在: ${INFRA_REPO_PATH}${NC}"
    exit 1
fi

# 目标文件路径
TARGET_FILE="${INFRA_REPO_PATH}/apisix/config/routes/${SERVICE_NAME}-routes.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}自动同步路由配置${NC}"
echo -e "${GREEN}========================================${NC}"
echo "服务名称: ${SERVICE_NAME}"
echo "源文件: ${ROUTES_FILE}"
echo "目标文件: ${TARGET_FILE}"
echo ""

# 进入主仓库目录
cd "$INFRA_REPO_PATH"

# 确保在正确的分支上（通常是 main 或 master）
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
    echo -e "${YELLOW}⚠ 当前分支: ${CURRENT_BRANCH}${NC}"
    echo -e "${YELLOW}  建议在 main/master 分支上同步${NC}"
    read -p "是否继续? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# 拉取最新更改
echo -e "${BLUE}拉取主仓库最新更改...${NC}"
git pull --rebase || {
    echo -e "${RED}❌ 拉取失败，请手动解决冲突后重试${NC}"
    exit 1
}

# 确保目标目录存在
mkdir -p "$(dirname "$TARGET_FILE")"

# 复制路由文件
echo -e "${BLUE}复制路由配置文件...${NC}"
cp "$(git rev-parse --show-toplevel)/${ROUTES_FILE}" "$TARGET_FILE"

# 添加注释说明来源
{
    echo "# ${SERVICE_NAME^} Service 路由配置"
    echo "# 自动同步自: $(git -C "$(git rev-parse --show-toplevel)" remote get-url origin 2>/dev/null || echo 'local')"
    echo "# 同步时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# 提交哈希: $(git -C "$(git rev-parse --show-toplevel)" rev-parse HEAD)"
    echo ""
    tail -n +1 "$TARGET_FILE"
} > "${TARGET_FILE}.tmp"
mv "${TARGET_FILE}.tmp" "$TARGET_FILE"

# 检查是否有更改
if git diff --quiet "$TARGET_FILE"; then
    echo -e "${YELLOW}⚠ 路由配置无更改，跳过提交${NC}"
    exit 0
fi

# 提交更改
echo -e "${BLUE}提交路由配置更改...${NC}"
git add "$TARGET_FILE"
git commit -m "chore: sync ${SERVICE_NAME} service routes from $(basename "$(git -C "$(git rev-parse --show-toplevel)" rev-parse --show-toplevel)")

Auto-synced from: $(git -C "$(git rev-parse --show-toplevel)" rev-parse HEAD)" || {
    echo -e "${YELLOW}⚠ 提交失败（可能没有更改）${NC}"
    exit 0
}

# 推送到远程（可选，可以通过环境变量控制）
if [ "${AUTO_PUSH:-false}" = "true" ]; then
    echo -e "${BLUE}推送到远程仓库...${NC}"
    git push || {
        echo -e "${YELLOW}⚠ 推送失败，请手动推送${NC}"
    }
else
    echo -e "${YELLOW}⚠ 未启用自动推送（设置 AUTO_PUSH=true 启用）${NC}"
    echo -e "${BLUE}请手动推送: cd ${INFRA_REPO_PATH} && git push${NC}"
fi

echo -e "${GREEN}✓ 路由配置已同步${NC}"
echo -e "${GREEN}========================================${NC}"
