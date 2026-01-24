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
        python3 <<PYTHON_SCRIPT
import re

service_name = None
methods = []

with open("$proto_file", "r") as f:
    content = f.read()
    
    # 提取 service 名称
    service_match = re.search(r'service\s+(\w+)\s*{', content)
    if service_match:
        service_name = service_match.group(1)
    
    # 提取 rpc 方法
    rpc_pattern = r'rpc\s+(\w+)\s*\([^)]+\)\s+returns\s+\([^)]+\)'
    methods = re.findall(rpc_pattern, content)

print(f"SERVICE_NAME={service_name}")
for i, method in enumerate(methods, 1):
    print(f"METHOD_{i}={method}")
PYTHON_SCRIPT
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
    
    case "$method_name" in
        Register|Create*)
            uri="${API_PREFIX}"
            if [[ "$method_name" == *"Register"* ]]; then
                uri="${API_PREFIX}/register"
            fi
            http_method="POST"
            ;;
        Login)
            uri="${API_PREFIX}/login"
            http_method="POST"
            ;;
        Get*|List*)
            uri="${API_PREFIX}/*"
            http_method="GET"
            ;;
        Update*)
            uri="${API_PREFIX}/*"
            http_method="PUT"
            ;;
        Delete*)
            uri="${API_PREFIX}/*"
            http_method="DELETE"
            ;;
        *)
            uri="${API_PREFIX}/${method_name,,}"
            http_method="POST"
            ;;
    esac
    
    # 生成路由名称
    local route_name="${SERVICE_NAME}-${method_name,,}"
    
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
    plugins:
      grpc-transcode:
        proto_id: "${PROTO_ID}"
        service: ${SERVICE_PACKAGE}.${SERVICE_NAME^}Service
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
    eval "$service_info"
    
    if [ -z "$SERVICE_NAME" ]; then
        echo "错误: 无法从 proto 文件提取服务名称"
        exit 1
    fi
    
    # 生成配置文件
    local output_file="${OUTPUT_DIR}/${SERVICE_NAME}-routes.yaml"
    
    {
        echo "# ${SERVICE_NAME^} Service 路由配置"
        echo "# 自动生成于: $(date)"
        echo "# Proto 文件: $PROTO_FILE"
        echo ""
        echo "routes:"
        
        # 为每个方法生成路由
        local method_num=1
        while eval [ -n "\${METHOD_${method_num}:-}" ]; do
            local method_name=$(eval echo "\$METHOD_${method_num}")
            generate_route_config "$method_name" "$method_num"
            ((method_num++))
        done
    } > "$output_file"
    
    echo -e "${GREEN}✓ 配置已生成: ${output_file}${NC}"
    echo ""
    echo "下一步:"
    echo "  1. 检查生成的配置: cat ${output_file}"
    echo "  2. 合并并部署: ./scripts/merge-apisix-configs.sh"
}

main "$@"
