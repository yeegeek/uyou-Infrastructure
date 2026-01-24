#!/bin/bash

# 快速安装 Git Hook 到微服务仓库
# 使用方法: ./install-hook.sh <微服务仓库路径> [服务名称]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_REPO_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/post-commit-sync-routes.sh"

# 检查参数
if [ $# -lt 1 ]; then
    echo -e "${RED}用法: $0 <微服务仓库路径> [服务名称]${NC}"
    echo ""
    echo "示例:"
    echo "  $0 /path/to/user-service user"
    echo "  $0 /path/to/order-service order"
    exit 1
fi

SERVICE_REPO_PATH="$1"
SERVICE_NAME="${2:-}"

# 检查微服务仓库是否存在
if [ ! -d "$SERVICE_REPO_PATH" ]; then
    echo -e "${RED}❌ 错误: 微服务仓库不存在: ${SERVICE_REPO_PATH}${NC}"
    exit 1
fi

# 检查是否是 Git 仓库
if [ ! -d "${SERVICE_REPO_PATH}/.git" ]; then
    echo -e "${RED}❌ 错误: 不是 Git 仓库: ${SERVICE_REPO_PATH}${NC}"
    exit 1
fi

# 检查路由文件是否存在
if [ ! -f "${SERVICE_REPO_PATH}/apisix/routes.yaml" ]; then
    echo -e "${YELLOW}⚠ 警告: 路由文件不存在: ${SERVICE_REPO_PATH}/apisix/routes.yaml${NC}"
    echo -e "${YELLOW}   请确保微服务仓库有 apisix/routes.yaml 文件${NC}"
    read -p "是否继续安装? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# 如果没有指定服务名称，从仓库名推断
if [ -z "$SERVICE_NAME" ]; then
    SERVICE_NAME=$(basename "$SERVICE_REPO_PATH")
    SERVICE_NAME="${SERVICE_NAME%-service}"
    SERVICE_NAME="${SERVICE_NAME#uyou-}"
    echo -e "${BLUE}ℹ 从仓库名推断服务名称: ${SERVICE_NAME}${NC}"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装 Git Hook${NC}"
echo -e "${GREEN}========================================${NC}"
echo "微服务仓库: ${SERVICE_REPO_PATH}"
echo "服务名称: ${SERVICE_NAME}"
echo "主仓库路径: ${INFRA_REPO_PATH}"
echo ""

# 复制 Hook 脚本
HOOK_PATH="${SERVICE_REPO_PATH}/.git/hooks/post-commit"
echo -e "${BLUE}复制 Hook 脚本...${NC}"
cp "$HOOK_SCRIPT" "$HOOK_PATH"
chmod +x "$HOOK_PATH"
echo -e "${GREEN}✓ Hook 脚本已安装: ${HOOK_PATH}${NC}"

# 创建配置文件
CONFIG_FILE="${SERVICE_REPO_PATH}/.infra-sync-config"
echo -e "${BLUE}创建配置文件...${NC}"
cat > "$CONFIG_FILE" <<EOF
# Git Hook 自动同步配置
# 自动生成于: $(date '+%Y-%m-%d %H:%M:%S')

INFRA_REPO_PATH=${INFRA_REPO_PATH}
SERVICE_NAME=${SERVICE_NAME}
AUTO_PUSH=false
EOF
echo -e "${GREEN}✓ 配置文件已创建: ${CONFIG_FILE}${NC}"

# 添加到 .gitignore（如果不存在）
if ! grep -q "^\.infra-sync-config$" "${SERVICE_REPO_PATH}/.gitignore" 2>/dev/null; then
    echo -e "${BLUE}添加到 .gitignore...${NC}"
    echo "" >> "${SERVICE_REPO_PATH}/.gitignore"
    echo "# Git Hook 配置文件（包含本地路径）" >> "${SERVICE_REPO_PATH}/.gitignore"
    echo ".infra-sync-config" >> "${SERVICE_REPO_PATH}/.gitignore"
    echo -e "${GREEN}✓ 已添加到 .gitignore${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "下一步："
echo "  1. 修改路由配置: vim ${SERVICE_REPO_PATH}/apisix/routes.yaml"
echo "  2. 提交更改: cd ${SERVICE_REPO_PATH} && git commit -am 'update routes'"
echo "  3. Hook 会自动同步到主仓库"
echo ""
echo "配置说明："
echo "  - 配置文件: ${CONFIG_FILE}"
echo "  - 可以编辑此文件修改设置（如启用 AUTO_PUSH=true）"
echo ""
