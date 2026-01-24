#!/bin/bash

# 验证 APISIX 路由配置
# 检查项：
# 1. YAML 语法正确性
# 2. 路由名称唯一性
# 3. URI 路径冲突
# 4. 必需字段完整性

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 配置目录
ROUTES_DIR="${ROUTES_DIR:-${PROJECT_ROOT}/apisix/config/routes}"
CONFIG_DIR="${CONFIG_DIR:-${PROJECT_ROOT}/apisix/config}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}APISIX 配置验证${NC}"
echo -e "${GREEN}========================================${NC}"
echo "路由目录: ${ROUTES_DIR}"
echo ""

# 错误计数
ERRORS=0
WARNINGS=0

# 检查依赖
check_dependencies() {
    local missing=()
    
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}错误: 缺少依赖: ${missing[*]}${NC}"
        exit 1
    fi
}

# 验证 YAML 语法
validate_yaml_syntax() {
    local file=$1
    local filename=$(basename "$file")
    
    echo -e "${BLUE}验证 YAML 语法: ${filename}${NC}"
    
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        echo -e "${GREEN}  ✓ YAML 语法正确${NC}"
        return 0
    else
        echo -e "${RED}  ✗ YAML 语法错误${NC}"
        python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>&1 | head -5
        ((ERRORS++))
        return 1
    fi
}

# 提取路由信息
extract_routes() {
    local file=$1
    
    python3 <<PYTHON_SCRIPT
import yaml
import sys

try:
    with open("$file", "r") as f:
        data = yaml.safe_load(f)
    
    routes = data.get("routes", [])
    for route in routes:
        name = route.get("name", "unnamed")
        uri = route.get("uri", "")
        methods = route.get("methods", [])
        print(f"{name}|{uri}|{','.join(methods)}")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

# 验证路由唯一性
validate_route_uniqueness() {
    echo -e "${BLUE}验证路由名称唯一性...${NC}"
    
    local route_names=()
    local duplicate_names=()
    
    # 收集所有路由名称
    for route_file in "${ROUTES_DIR}"/*.yaml "${CONFIG_DIR}/apisix.yaml" 2>/dev/null; do
        if [ ! -f "$route_file" ]; then
            continue
        fi
        
        while IFS='|' read -r name uri methods; do
            if [ -n "$name" ] && [ "$name" != "unnamed" ]; then
                if [[ " ${route_names[@]} " =~ " ${name} " ]]; then
                    duplicate_names+=("$name")
                else
                    route_names+=("$name")
                fi
            fi
        done < <(extract_routes "$route_file")
    done
    
    if [ ${#duplicate_names[@]} -gt 0 ]; then
        echo -e "${RED}  ✗ 发现重复的路由名称:${NC}"
        printf "    %s\n" "${duplicate_names[@]}"
        ((ERRORS++))
        return 1
    else
        echo -e "${GREEN}  ✓ 所有路由名称唯一 (共 ${#route_names[@]} 个)${NC}"
        return 0
    fi
}

# 验证 URI 冲突
validate_uri_conflicts() {
    echo -e "${BLUE}验证 URI 路径冲突...${NC}"
    
    local uri_map=()
    local conflicts=()
    
    # 收集所有 URI
    for route_file in "${ROUTES_DIR}"/*.yaml "${CONFIG_DIR}/apisix.yaml" 2>/dev/null; do
        if [ ! -f "$route_file" ]; then
            continue
        fi
        
        while IFS='|' read -r name uri methods; do
            if [ -n "$uri" ]; then
                # 检查冲突（简化版：完全匹配）
                for existing in "${uri_map[@]}"; do
                    if [ "$existing" = "$uri" ]; then
                        conflicts+=("$uri")
                    fi
                done
                uri_map+=("$uri|$name|$methods")
            fi
        done < <(extract_routes "$route_file")
    done
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        echo -e "${YELLOW}  ⚠ 发现可能的 URI 冲突:${NC}"
        printf "    %s\n" "${conflicts[@]}"
        ((WARNINGS++))
        return 1
    else
        echo -e "${GREEN}  ✓ 未发现 URI 冲突${NC}"
        return 0
    fi
}

# 验证必需字段
validate_required_fields() {
    echo -e "${BLUE}验证必需字段...${NC}"
    
    local missing_fields=0
    
    for route_file in "${ROUTES_DIR}"/*.yaml "${CONFIG_DIR}/apisix.yaml" 2>/dev/null; do
        if [ ! -f "$route_file" ]; then
            continue
        fi
        
        local filename=$(basename "$route_file")
        
        python3 <<PYTHON_SCRIPT
import yaml
import sys

try:
    with open("$route_file", "r") as f:
        data = yaml.safe_load(f)
    
    routes = data.get("routes", [])
    for i, route in enumerate(routes):
        missing = []
        
        if not route.get("name"):
            missing.append("name")
        if not route.get("uri"):
            missing.append("uri")
        if not route.get("methods"):
            missing.append("methods")
        if not route.get("upstream"):
            missing.append("upstream")
        
        if missing:
            print(f"  ✗ 路由 #{i+1} 缺少字段: {', '.join(missing)}", file=sys.stderr)
            sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
        
        if [ $? -ne 0 ]; then
            ((ERRORS++))
            missing_fields=1
        fi
    done
    
    if [ $missing_fields -eq 0 ]; then
        echo -e "${GREEN}  ✓ 所有路由包含必需字段${NC}"
        return 0
    else
        return 1
    fi
}

# 主函数
main() {
    check_dependencies
    
    # 检查路由目录
    if [ ! -d "$ROUTES_DIR" ]; then
        echo -e "${YELLOW}⚠ 路由目录不存在: ${ROUTES_DIR}${NC}"
        echo "创建目录..."
        mkdir -p "$ROUTES_DIR"
    fi
    
    # 检查是否有路由文件
    local route_files=("${ROUTES_DIR}"/*.yaml "${CONFIG_DIR}/apisix.yaml" 2>/dev/null)
    if [ ! -f "${route_files[0]}" ]; then
        echo -e "${YELLOW}⚠ 未找到路由配置文件${NC}"
        echo "请先运行: ./scripts/sync-routes.sh"
        exit 0
    fi
    
    # 执行验证
    echo ""
    for route_file in "${ROUTES_DIR}"/*.yaml "${CONFIG_DIR}/apisix.yaml" 2>/dev/null; do
        if [ -f "$route_file" ]; then
            validate_yaml_syntax "$route_file"
        fi
    done
    
    echo ""
    validate_route_uniqueness
    
    echo ""
    validate_uri_conflicts
    
    echo ""
    validate_required_fields
    
    # 总结
    echo ""
    echo -e "${GREEN}========================================${NC}"
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✓ 配置验证通过！${NC}"
        echo -e "${GREEN}========================================${NC}"
        exit 0
    else
        echo -e "${YELLOW}验证完成，发现问题：${NC}"
        echo "  错误: ${ERRORS}"
        echo "  警告: ${WARNINGS}"
        echo -e "${GREEN}========================================${NC}"
        if [ $ERRORS -gt 0 ]; then
            exit 1
        fi
    fi
}

# 运行主函数
main "$@"
