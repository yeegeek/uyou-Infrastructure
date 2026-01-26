#!/bin/bash

# 从 proto 文件自动生成 APISIX 路由配置
# 适用于微服务独立开发的场景

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 配置
SERVICE_NAME="${1:-}"
PROTO_FILE="${2:-}"
OUTPUT_DIR="${3:-${PROJECT_ROOT}/apisix/config/routes}"

usage() {
    cat <<EOF
用法: $0 <service-name> <proto-file> [output-dir]

参数:
  service-name  微服务名称 (如: user, order, feed)
  proto-file    Proto 文件路径
  output-dir    输出目录 (默认: apisix/config/routes)

示例:
  $0 user proto/user.proto
  $0 order proto/order.proto apisix/config/routes

环境变量:
  SERVICE_HOST  服务主机地址 (默认: <service-name>-service)
  SERVICE_PORT  服务端口 (默认: 50051, 50052, 50053)
  PROTO_ID      Proto ID (默认: 1, 2, 3)
EOF
    exit 1
}

# 检查参数
if [ -z "$SERVICE_NAME" ] || [ -z "$PROTO_FILE" ]; then
    usage
fi

# 检查 proto 文件是否存在
if [ ! -f "$PROTO_FILE" ]; then
    echo "错误: Proto 文件不存在: $PROTO_FILE"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 根据服务名设置默认值
case "$SERVICE_NAME" in
    user)
        SERVICE_HOST="${SERVICE_HOST:-user-service}"
        SERVICE_PORT="${SERVICE_PORT:-50051}"
        PROTO_ID="${PROTO_ID:-1}"
        SERVICE_PACKAGE="user"
        API_PREFIX="/api/v1/users"
        ;;
    order)
        SERVICE_HOST="${SERVICE_HOST:-order-service}"
        SERVICE_PORT="${SERVICE_PORT:-50052}"
        PROTO_ID="${PROTO_ID:-2}"
        SERVICE_PACKAGE="order"
        API_PREFIX="/api/v1/orders"
        ;;
    feed)
        SERVICE_HOST="${SERVICE_HOST:-feed-service}"
        SERVICE_PORT="${SERVICE_PORT:-50053}"
        PROTO_ID="${PROTO_ID:-3}"
        SERVICE_PACKAGE="feed"
        API_PREFIX="/api/v1/feeds"
        ;;
    *)
        echo "错误: 未知的服务名称: $SERVICE_NAME"
        echo "支持的服务: user, order, feed"
        exit 1
        ;;
esac

# 从 proto 文件提取服务和方法
extract_service_info() {
    local proto_file=$1
    
    if command -v python3 &> /dev/null; then
        # 使用临时 Python 脚本文件，避免引号转义问题
        local tmp_script=$(mktemp)
        cat > "$tmp_script" <<'PYTHON_SCRIPT'
import re
import sys

proto_file = sys.argv[1]

try:
    with open(proto_file, 'r') as f:
        content = f.read()
    
    # 提取 service 名称
    service_name = None
    service_match = re.search(r'service\s+(\w+)\s*{', content)
    if service_match:
        service_name = service_match.group(1)
    
    # 提取 rpc 方法
    methods = []
    rpc_pattern = r'rpc\s+(\w+)\s*\([^)]+\)\s+returns\s+\([^)]+\)'
    methods = re.findall(rpc_pattern, content)
    
    if service_name:
        print(f'SERVICE_NAME={service_name}')
    for i, method in enumerate(methods, 1):
        print(f'METHOD_{i}={method}')
except Exception as e:
    print(f'错误: {e}', file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
        python3 "$tmp_script" "$proto_file"
        rm -f "$tmp_script"
    else
        # 简单的 grep 方式（不够准确，但可用）
        echo "SERVICE_NAME=$(grep -oP 'service\s+\K\w+' "$proto_file" | head -1)"
        grep -oP 'rpc\s+\K\w+' "$proto_file" | nl -v 0 -n ln | sed 's/^[[:space:]]*\([0-9]*\)[[:space:]]*\(.*\)/METHOD_\1=\2/'
    fi
}

# 生成路由配置
generate_route_config() {
    local method_name=$1
    local method_num=$2
    
    # 根据方法名生成 URI 和 HTTP 方法
    local uri=""
    local http_method="POST"
    local require_auth=false
    
    case "$method_name" in
        Register|Create*)
            uri="${API_PREFIX}"
            if [[ "$method_name" == *"Register"* ]]; then
                uri="${API_PREFIX}/register"
                require_auth=false  # 注册接口不需要认证
            else
                require_auth=true   # 其他创建接口需要认证
            fi
            http_method="POST"
            ;;
        Login)
            uri="${API_PREFIX}/login"
            http_method="POST"
            require_auth=false  # 登录接口不需要认证
            ;;
        Get*|List*)
            uri="${API_PREFIX}/*"
            http_method="GET"
            require_auth=true   # 查询接口需要认证
            ;;
        Update*)
            uri="${API_PREFIX}/*"
            http_method="PUT"
            require_auth=true   # 更新接口需要认证
            ;;
        Delete*)
            uri="${API_PREFIX}/*"
            http_method="DELETE"
            require_auth=true   # 删除接口需要认证
            ;;
        *)
            # 将方法名转换为小写（兼容性处理）
            method_name_lower=$(echo "$method_name" | tr '[:upper:]' '[:lower:]')
            uri="${API_PREFIX}/${method_name_lower}"
            http_method="POST"
            require_auth=true   # 默认需要认证
            ;;
    esac
    
    # 生成路由名称（将方法名转换为小写）
    local method_name_lower=$(echo "$method_name" | tr '[:upper:]' '[:lower:]')
    local route_name="${SERVICE_NAME}-${method_name_lower}"
    
    # 生成 YAML 配置
    cat <<EOF
  - name: ${route_name}
    uri: ${uri}
    methods: [${http_method}]
    upstream:
      type: roundrobin
      nodes:
        "${SERVICE_HOST}:${SERVICE_PORT}": 1
      scheme: grpc
    plugins:$(if [ "$require_auth" = true ]; then echo -e "\n      jwt-auth: {}"; fi)
      grpc-transcode:
        proto_id: "${PROTO_ID}"
        service: ${SERVICE_PACKAGE}.$(echo "$SERVICE_NAME" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')Service
        method: ${method_name}
        show_status_in_body: true
        pb_option: ["enum_as_name", "int64_as_number", "auto_default_values"]
      cors:
        allow_origins: "*"
        allow_methods: "GET,POST,PUT,DELETE,OPTIONS"
        allow_headers: "*"
EOF
}

# 主函数
main() {
    echo -e "${GREEN}生成 ${SERVICE_NAME} 服务的路由配置...${NC}"
    
    # 提取服务信息
    local service_info=$(extract_service_info "$PROTO_FILE")
    
    # 安全地解析提取的信息
    local extracted_service_name=""
    local methods=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^SERVICE_NAME=(.+)$ ]]; then
            extracted_service_name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^METHOD_([0-9]+)=(.+)$ ]]; then
            local method_num="${BASH_REMATCH[1]}"
            local method_name="${BASH_REMATCH[2]}"
            methods+=("$method_name")
        fi
    done <<< "$service_info"
    
    if [ -z "$extracted_service_name" ] && [ ${#methods[@]} -eq 0 ]; then
        echo "错误: 无法从 proto 文件提取服务信息"
        echo "提取的输出: $service_info"
        exit 1
    fi
    
    # 生成配置文件
    local output_file="${OUTPUT_DIR}/${SERVICE_NAME}-routes.yaml"
    
    # 首字母大写（兼容性处理）
    SERVICE_NAME_CAPITALIZED=$(echo "$SERVICE_NAME" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    
    {
        echo "# ${SERVICE_NAME_CAPITALIZED} Service 路由配置"
        echo "# 自动生成于: $(date)"
        echo "# Proto 文件: $PROTO_FILE"
        echo "# 注意: 这是自动生成的模板，请根据实际需求手动调整"
        echo ""
        echo "routes:"
        
        # 为每个方法生成路由
        local method_num=1
        for method_name in "${methods[@]}"; do
            generate_route_config "$method_name" "$method_num"
            ((method_num++))
        done
    } > "$output_file"
    
    echo -e "${GREEN}✓ 配置已生成: ${output_file}${NC}"
    echo ""
    echo "⚠ 注意: 这是自动生成的模板配置，可能不够准确"
    echo "   请根据实际 proto 定义和业务需求手动调整路由配置"
    echo ""
    echo "下一步:"
    echo "  1. 检查生成的配置: cat ${output_file}"
    echo "  2. 手动调整路由配置（URI、方法映射等）"
    echo "  3. 合并并部署: make update-apisix-merge"
}

main "$@"
