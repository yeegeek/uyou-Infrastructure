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

# 创建临时 proto 文件
TEMP_DIR=$(mktemp -d)

# Proto 1: User Service
cat > "${TEMP_DIR}/proto1.proto" <<'PROTO1_EOF'
syntax = "proto3";
package user;
service UserService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc UpdateUser(UpdateUserRequest) returns (UpdateUserResponse);
}
message RegisterRequest {
  string username = 1;
  string email = 2;
  string password = 3;
}
message RegisterResponse {
  int64 user_id = 1;
  string message = 2;
}
message LoginRequest {
  string username = 1;
  string password = 2;
}
message LoginResponse {
  string token = 1;
  int64 user_id = 2;
  string username = 3;
}
message GetUserRequest {
  int64 user_id = 1;
}
message GetUserResponse {
  int64 user_id = 1;
  string username = 2;
  string email = 3;
  string avatar = 4;
  string created_at = 5;
}
message UpdateUserRequest {
  int64 user_id = 1;
  string email = 2;
  string avatar = 3;
}
message UpdateUserResponse {
  bool success = 1;
  string message = 2;
}
PROTO1_EOF

# Proto 2: Order Service
cat > "${TEMP_DIR}/proto2.proto" <<'PROTO2_EOF'
syntax = "proto3";
package order;
service OrderService {
  rpc CreateOrder(CreateOrderRequest) returns (CreateOrderResponse);
  rpc GetOrder(GetOrderRequest) returns (GetOrderResponse);
}
message OrderItem {
  int64 product_id = 1;
  string product_name = 2;
  int32 quantity = 3;
  double price = 4;
}
message CreateOrderRequest {
  int64 user_id = 1;
  repeated OrderItem items = 2;
  double total_amount = 3;
}
message CreateOrderResponse {
  int64 order_id = 1;
  string order_no = 2;
  string message = 3;
}
message GetOrderRequest {
  int64 order_id = 1;
}
message GetOrderResponse {
  int64 order_id = 1;
  string order_no = 2;
  int64 user_id = 3;
  repeated OrderItem items = 4;
  double total_amount = 5;
  string status = 6;
  string created_at = 7;
}
PROTO2_EOF

# Proto 3: Feed Service
cat > "${TEMP_DIR}/proto3.proto" <<'PROTO3_EOF'
syntax = "proto3";
package feed;
service FeedService {
  rpc CreateFeed(CreateFeedRequest) returns (CreateFeedResponse);
  rpc GetFeed(GetFeedRequest) returns (GetFeedResponse);
}
message CreateFeedRequest {
  int64 user_id = 1;
  string content = 2;
  repeated string images = 3;
  string location = 4;
}
message CreateFeedResponse {
  string feed_id = 1;
  string message = 2;
}
message GetFeedRequest {
  string feed_id = 1;
}
message GetFeedResponse {
  string feed_id = 1;
  int64 user_id = 2;
  string content = 3;
  repeated string images = 4;
  string location = 5;
  int32 likes = 6;
  int32 comments = 7;
  string created_at = 8;
}
PROTO3_EOF

# 创建 Proto 定义
create_proto "1" "${TEMP_DIR}/proto1.proto"
create_proto "2" "${TEMP_DIR}/proto2.proto"
create_proto "3" "${TEMP_DIR}/proto3.proto"

# 清理临时文件
rm -rf "$TEMP_DIR"

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
