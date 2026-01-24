#!/bin/bash

# 从微服务仓库同步路由配置到 APISIX 配置目录
# 支持两种模式：
# 1. Git Submodule 模式：从 services/ 目录下的 submodule 同步
# 2. 直接路径模式：从指定的微服务目录同步

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 配置目录
SERVICES_DIR="${SERVICES_DIR:-${PROJECT_ROOT}/services}"
ROUTES_DIR="${ROUTES_DIR:-${PROJECT_ROOT}/apisix/config/routes}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}同步微服务路由配置${NC}"
echo -e "${GREEN}========================================${NC}"
echo "服务目录: ${SERVICES_DIR}"
echo "路由目录: ${ROUTES_DIR}"
echo ""

# 创建路由目录
mkdir -p "$ROUTES_DIR"

# 同步单个服务的路由配置
sync_service_routes() {
    local service_name=$1
    local service_dir=$2
    local routes_file="${service_dir}/apisix/routes.yaml"
    local output_file="${ROUTES_DIR}/${service_name}-routes.yaml"
    
    if [ ! -d "$service_dir" ]; then
        echo -e "${YELLOW}⚠ 跳过不存在的服务目录: ${service_dir}${NC}"
        return 0
    fi
    
    if [ ! -f "$routes_file" ]; then
        echo -e "${YELLOW}⚠ 跳过不存在的路由文件: ${routes_file}${NC}"
        return 0
    fi
    
    echo -e "${BLUE}同步 ${service_name} 服务路由...${NC}"
    
    # 复制文件
    cp "$routes_file" "$output_file"
    
    # 添加注释说明来源
    {
        echo "# ${service_name^} Service 路由配置"
        echo "# 自动同步自: ${service_dir}/apisix/routes.yaml"
        echo "# 同步时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        cat "$output_file"
    } > "${output_file}.tmp"
    mv "${output_file}.tmp" "$output_file"
    
    echo -e "${GREEN}  ✓ ${service_name} 路由已同步到 ${output_file}${NC}"
}

# 主函数
main() {
    local sync_count=0
    
    # 方式 1: 从 services/ 目录同步（支持 submodule）
    if [ -d "$SERVICES_DIR" ]; then
        echo -e "${BLUE}从 services/ 目录同步路由配置...${NC}"
        
        for service_dir in "$SERVICES_DIR"/*; do
            if [ -d "$service_dir" ]; then
                local service_name=$(basename "$service_dir")
                
                # 跳过隐藏目录和非服务目录
                if [[ "$service_name" == .* ]] || [ ! -f "${service_dir}/apisix/routes.yaml" ]; then
                    continue
                fi
                
                sync_service_routes "$service_name" "$service_dir"
                ((sync_count++))
            fi
        done
    fi
    
    # 方式 2: 从环境变量指定的服务目录同步
    if [ -n "$USER_SERVICE_DIR" ]; then
        echo -e "${BLUE}从指定目录同步 user-service...${NC}"
        sync_service_routes "user" "$USER_SERVICE_DIR"
        ((sync_count++))
    fi
    
    if [ -n "$ORDER_SERVICE_DIR" ]; then
        echo -e "${BLUE}从指定目录同步 order-service...${NC}"
        sync_service_routes "order" "$ORDER_SERVICE_DIR"
        ((sync_count++))
    fi
    
    if [ -n "$FEED_SERVICE_DIR" ]; then
        echo -e "${BLUE}从指定目录同步 feed-service...${NC}"
        sync_service_routes "feed" "$FEED_SERVICE_DIR"
        ((sync_count++))
    fi
    
    # 总结
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}同步完成！${NC}"
    echo "已同步服务数: ${sync_count}"
    echo "路由配置目录: ${ROUTES_DIR}"
    echo -e "${GREEN}========================================${NC}"
    
    # 列出同步的文件
    if [ $sync_count -gt 0 ]; then
        echo ""
        echo "已同步的路由配置文件:"
        ls -lh "${ROUTES_DIR}"/*.yaml 2>/dev/null | awk '{print "  - " $9}'
    else
        echo -e "${YELLOW}⚠ 没有找到任何路由配置文件${NC}"
        echo ""
        echo "提示："
        echo "  1. 确保微服务目录存在: ${SERVICES_DIR}"
        echo "  2. 确保每个服务有 apisix/routes.yaml 文件"
        echo "  3. 或使用环境变量指定服务目录:"
        echo "     USER_SERVICE_DIR=/path/to/user-service"
        echo "     ORDER_SERVICE_DIR=/path/to/order-service"
    fi
}

# 运行主函数
main "$@"
