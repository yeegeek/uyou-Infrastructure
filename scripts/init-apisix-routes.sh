#!/bin/bash

# 初始化 APISIX 路由配置脚本
# 通过 Admin API 将路由配置推送到 etcd

GATEWAY_URL="http://localhost:9180"
ADMIN_KEY="edd1c9f034335f136f87ad84b625c8f1"

echo "正在初始化 APISIX 路由配置..."

# 等待 APISIX 就绪
echo "等待 APISIX 服务就绪..."
for i in {1..60}; do
    if curl -s -f "${GATEWAY_URL}/apisix/admin/routes" -H "X-API-KEY: ${ADMIN_KEY}" > /dev/null 2>&1; then
        echo "APISIX 已就绪"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "错误: APISIX 服务未就绪，请检查服务状态: docker compose ps apisix"
        exit 1
    fi
    sleep 2
done

# 函数：创建路由
create_route() {
    local name=$1
    local uri=$2
    local method=$3
    local upstream=$4
    local proto_id=$5
    local service=$6
    local method_name=$7
    
    local route_config=$(cat <<EOF
{
  "uri": "${uri}",
  "name": "${name}",
  "methods": ["${method}"],
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "${upstream}": 1
    },
    "scheme": "grpc"
  },
  "plugins": {
    "grpc-transcode": {
      "proto_id": "${proto_id}",
      "service": "${service}",
      "method": "${method_name}",
      "show_status_in_body": true,
      "pb_option": ["enum_as_name", "int64_as_number", "auto_default_values"]
    },
    "cors": {
      "allow_origins": "*",
      "allow_methods": "GET,POST,PUT,DELETE,OPTIONS",
      "allow_headers": "*"
    }
  }
}
EOF
)
    
    echo "创建路由: ${name} (${method} ${uri})"
    response=$(curl -s -X PUT "${GATEWAY_URL}/apisix/admin/routes/${name}" \
        -H "X-API-KEY: ${ADMIN_KEY}" \
        -H "Content-Type: application/json" \
        -d "${route_config}")
    
    if echo "$response" | grep -q '"key"'; then
        echo "  ✓ 成功"
    else
        echo "  ✗ 失败: $response"
    fi
}

# 函数：创建带通配符的路由
create_wildcard_route() {
    local name=$1
    local uri=$2
    local method=$3
    local upstream=$4
    local proto_id=$5
    local service=$6
    local method_name=$7
    
    local route_config=$(cat <<EOF
{
  "uri": "${uri}",
  "name": "${name}",
  "methods": ["${method}"],
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "${upstream}": 1
    },
    "scheme": "grpc"
  },
  "plugins": {
    "grpc-transcode": {
      "proto_id": "${proto_id}",
      "service": "${service}",
      "method": "${method_name}",
      "show_status_in_body": true,
      "pb_option": ["enum_as_name", "int64_as_number", "auto_default_values"]
    },
    "cors": {
      "allow_origins": "*",
      "allow_methods": "GET,POST,PUT,DELETE,OPTIONS",
      "allow_headers": "*"
    }
  }
}
EOF
)
    
    echo "创建路由: ${name} (${method} ${uri})"
    response=$(curl -s -X PUT "${GATEWAY_URL}/apisix/admin/routes/${name}" \
        -H "X-API-KEY: ${ADMIN_KEY}" \
        -H "Content-Type: application/json" \
        -d "${route_config}")
    
    if echo "$response" | grep -q '"key"'; then
        echo "  ✓ 成功"
    else
        echo "  ✗ 失败: $response"
    fi
}

# 首先创建 Proto 定义
echo -e "\n创建 Proto 定义..."

# 函数：创建 Proto 定义（使用临时文件避免转义问题）
create_proto() {
    local id=$1
    local proto_file=$2
    
    echo "创建 Proto ${id}..."
    
    # 使用临时文件构建 JSON
    local temp_json=$(mktemp)
    if command -v jq &> /dev/null; then
        jq -n --arg id "$id" --rawfile content "$proto_file" '{id: $id, content: $content}' > "$temp_json"
    else
        python3 <<PYTHON_SCRIPT > "$temp_json"
import json
with open("$proto_file", "r") as f:
    content = f.read()
print(json.dumps({"id": "$id", "content": content}))
PYTHON_SCRIPT
    fi
    
    response=$(curl -s -X PUT "${GATEWAY_URL}/apisix/admin/protos/${id}" \
        -H "X-API-KEY: ${ADMIN_KEY}" \
        -H "Content-Type: application/json" \
        -d "@${temp_json}")
    
    rm -f "$temp_json"
    
    if echo "$response" | grep -q '"key"'; then
        echo "  ✓ Proto ${id} 创建成功"
    else
        echo "  ✗ Proto ${id} 创建失败: $response"
    fi
}

# 从 proto 文件读取并创建 Proto 定义
# 获取脚本所在目录的父目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROTO_DIR="${PROJECT_ROOT}/proto"

# 检查 proto 文件是否存在
if [ ! -f "${PROTO_DIR}/user.proto" ]; then
    echo "错误: 找不到 ${PROTO_DIR}/user.proto"
    exit 1
fi

# 创建 Proto 定义（直接从 proto 文件读取）
create_proto "1" "${PROTO_DIR}/user.proto"
create_proto "2" "${PROTO_DIR}/order.proto"
create_proto "3" "${PROTO_DIR}/feed.proto"

echo "Proto 定义创建完成"

# 创建 User Service 路由
echo -e "\n创建 User Service 路由..."
create_route "user-register" "/api/v1/users/register" "POST" "user-service:50051" "1" "user.UserService" "Register"
create_route "user-login" "/api/v1/users/login" "POST" "user-service:50051" "1" "user.UserService" "Login"
create_wildcard_route "user-get" "/api/v1/users/*" "GET" "user-service:50051" "1" "user.UserService" "GetUser"

# 创建 Order Service 路由
echo -e "\n创建 Order Service 路由..."
create_route "order-create" "/api/v1/orders" "POST" "order-service:50052" "2" "order.OrderService" "CreateOrder"
create_wildcard_route "order-get" "/api/v1/orders/*" "GET" "order-service:50052" "2" "order.OrderService" "GetOrder"

# 创建 Feed Service 路由
echo -e "\n创建 Feed Service 路由..."
create_route "feed-create" "/api/v1/feeds" "POST" "feed-service:50053" "3" "feed.FeedService" "CreateFeed"
create_wildcard_route "feed-get" "/api/v1/feeds/*" "GET" "feed-service:50053" "3" "feed.FeedService" "GetFeed"

echo -e "\n路由配置完成！"
echo "现在可以测试 API 了："
echo "  curl -X POST http://localhost:9080/api/v1/users/register -H 'Content-Type: application/json' -d '{\"username\":\"demo\",\"email\":\"demo@example.com\",\"password\":\"demo123\"}'"
