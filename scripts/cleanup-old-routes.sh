#!/bin/bash

# 清理旧的路由配置（没有 jwt-auth 插件的路由）
# 用于清理之前部署的旧路由

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置
GATEWAY_URL="${APISIX_ADMIN_URL:-http://localhost:9180}"
ADMIN_KEY="${APISIX_ADMIN_KEY:-edd1c9f034335f136f87ad84b625c8f1}"

echo -e "${YELLOW}清理旧路由配置...${NC}"

# 获取所有路由
routes_response=$(curl -s "${GATEWAY_URL}/apisix/admin/routes" \
    -H "X-API-KEY: ${ADMIN_KEY}")

# 使用 Python 解析并找出需要清理的路由
python3 <<PYTHON_SCRIPT
import json
import sys

routes_data = json.loads("""$routes_response""")
routes_to_delete = []

# 定义应该保留的路由名称（新路由）
valid_routes = {
    'user-register', 'user-login', 'user-getuser', 'user-updateuser',
    'order-createorder', 'order-getorder', 'order-listorders', 'order-updateorderstatus',
    'feed-createfeed', 'feed-getfeed', 'feed-listfeeds', 'feed-deletefeed', 'feed-likefeed'
}

for route in routes_data.get('list', []):
    route_value = route.get('value', {})
    route_name = route_value.get('name', '')
    route_uri = route_value.get('uri', '')
    plugins = route_value.get('plugins', {})
    has_jwt = 'jwt-auth' in plugins
    
    # 检查是否需要清理：
    # 1. 路由名称不在有效列表中，且 URI 匹配我们的 API 路径
    # 2. 或者路由名称在有效列表中但没有 jwt-auth（旧版本）
    if route_uri.startswith('/api/v1/'):
        if route_name not in valid_routes:
            # 旧路由，需要删除
            routes_to_delete.append((route_name, route_uri, '旧路由（不在有效列表中）'))
        elif route_name in valid_routes and not has_jwt:
            # 有效路由但没有 jwt-auth，可能是旧版本
            routes_to_delete.append((route_name, route_uri, '旧版本（缺少 jwt-auth）'))

if routes_to_delete:
    print(f"找到 {len(routes_to_delete)} 个需要清理的路由：")
    for name, uri, reason in routes_to_delete:
        print(f"  - {name}: {uri} ({reason})")
    print("\n路由名称列表（用于删除）：")
    for name, _, _ in routes_to_delete:
        print(name)
else:
    print("没有需要清理的路由")
PYTHON_SCRIPT

echo ""
read -p "是否删除这些路由？(y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消"
    exit 0
fi

# 删除路由
python3 <<PYTHON_SCRIPT
import json
import subprocess

routes_data = json.loads("""$routes_response""")
valid_routes = {
    'user-register', 'user-login', 'user-getuser', 'user-updateuser',
    'order-createorder', 'order-getorder', 'order-listorders', 'order-updateorderstatus',
    'feed-createfeed', 'feed-getfeed', 'feed-listfeeds', 'feed-deletefeed', 'feed-likefeed'
}

deleted_count = 0
for route in routes_data.get('list', []):
    route_value = route.get('value', {})
    route_name = route_value.get('name', '')
    route_uri = route_value.get('uri', '')
    plugins = route_value.get('plugins', {})
    has_jwt = 'jwt-auth' in plugins
    
    should_delete = False
    if route_uri.startswith('/api/v1/'):
        if route_name not in valid_routes:
            should_delete = True
        elif route_name in valid_routes and not has_jwt:
            should_delete = True
    
    if should_delete:
        result = subprocess.run([
            'curl', '-s', '-X', 'DELETE',
            f'${GATEWAY_URL}/apisix/admin/routes/{route_name}',
            '-H', f'X-API-KEY: ${ADMIN_KEY}'
        ], capture_output=True, text=True)
        if 'deleted' in result.stdout:
            print(f"✓ 已删除: {route_name}")
            deleted_count += 1
        else:
            print(f"✗ 删除失败: {route_name}")

print(f"\n共删除 {deleted_count} 个路由")
PYTHON_SCRIPT

echo -e "${GREEN}清理完成！${NC}"
