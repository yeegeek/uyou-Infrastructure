#!/bin/bash

# 测试 JWT 认证的脚本
# 使用方法: ./examples/auth/test_auth.sh

set -e

GATEWAY_URL="${APISIX_GATEWAY_URL:-http://localhost:9080}"

echo "=========================================="
echo "微服务安全认证测试脚本"
echo "=========================================="
echo ""

# 测试 JWT 认证
echo "=== 测试 JWT 认证 ==="
echo ""

# 1. 注册用户（不需要 token）
echo "1. 注册用户（公开接口，不需要 token）..."
REGISTER_RESPONSE=$(curl -s -X POST "${GATEWAY_URL}/api/v1/users/register" \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com","password":"test123"}')

echo "响应: $REGISTER_RESPONSE"
echo ""

# 2. 登录获取 token
echo "2. 登录获取 token（公开接口，返回 JWT token）..."
LOGIN_RESPONSE=$(curl -s -X POST "${GATEWAY_URL}/api/v1/users/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"test123"}')

TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || echo "")

if [ -z "$TOKEN" ]; then
    echo "⚠ 警告: 无法从登录响应中提取 token"
    echo "响应: $LOGIN_RESPONSE"
    echo ""
    echo "提示: 请确保用户服务已启动并正常工作"
    TOKEN="dummy-token-for-testing"
else
    echo "✓ 成功获取 JWT Token: ${TOKEN:0:20}..."
    echo ""
fi

# 3. 使用 token 访问受保护接口
echo "3. 使用 token 访问受保护接口（应该成功）..."
PROTECTED_RESPONSE=$(curl -s -X GET "${GATEWAY_URL}/api/v1/users/1" \
  -H "Authorization: Bearer $TOKEN")

if echo "$PROTECTED_RESPONSE" | grep -q "401\|Unauthorized\|missing\|invalid"; then
    echo "✗ 失败: $PROTECTED_RESPONSE"
else
    echo "✓ 成功: 已访问受保护接口"
    echo "响应: $PROTECTED_RESPONSE"
fi
echo ""

# 4. 无 token 访问受保护接口（应该失败）
echo "4. 无 token 访问受保护接口（应该返回 401）..."
NO_TOKEN_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "${GATEWAY_URL}/api/v1/users/1")

HTTP_CODE=$(echo "$NO_TOKEN_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$NO_TOKEN_RESPONSE" | grep -v "HTTP_CODE:")

if [ "$HTTP_CODE" = "401" ]; then
    echo "✓ 正确: 返回 401 Unauthorized"
    echo "响应: $BODY"
else
    echo "⚠ 警告: 期望返回 401，但实际返回: $HTTP_CODE"
    echo "响应: $BODY"
fi
echo ""

echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""
echo "提示:"
echo "  1. 确保所有服务已启动: docker compose up -d"
echo "  2. 确保路由已部署: make update-apisix-merge"
echo "  3. 检查服务日志以获取更多信息"
