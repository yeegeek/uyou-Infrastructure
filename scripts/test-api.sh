#!/bin/bash

# API 测试脚本
# 用于测试 APISIX Gateway 的 REST API 接口

GATEWAY_URL="http://localhost:9080"

echo "================================"
echo "测试 User Service API"
echo "================================"

# 1. 用户注册
echo -e "\n1. 测试用户注册..."
curl -X POST "${GATEWAY_URL}/api/v1/users/register" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser123",
    "email": "testuser123@example.com",
    "password": "password123"
  }' | jq .

# 2. 用户登录
echo -e "\n2. 测试用户登录..."
LOGIN_RESPONSE=$(curl -s -X POST "${GATEWAY_URL}/api/v1/users/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser123",
    "password": "password123"
  }')
echo $LOGIN_RESPONSE | jq .

# 提取 token 和 user_id
TOKEN=$(echo $LOGIN_RESPONSE | jq -r '.token')
USER_ID=$(echo $LOGIN_RESPONSE | jq -r '.user_id')

# 3. 获取用户信息
echo -e "\n3. 测试获取用户信息..."
curl -X GET "${GATEWAY_URL}/api/v1/users/${USER_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | jq .

echo -e "\n================================"
echo "测试 Order Service API"
echo "================================"

# 4. 创建订单
echo -e "\n4. 测试创建订单..."
ORDER_RESPONSE=$(curl -s -X POST "${GATEWAY_URL}/api/v1/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{
    \"user_id\": ${USER_ID},
    \"items\": [
      {
        \"product_id\": 1001,
        \"product_name\": \"测试商品A\",
        \"quantity\": 2,
        \"price\": 99.99
      },
      {
        \"product_id\": 1002,
        \"product_name\": \"测试商品B\",
        \"quantity\": 1,
        \"price\": 49.99
      }
    ],
    \"total_amount\": 249.97
  }")
echo $ORDER_RESPONSE | jq .

ORDER_ID=$(echo $ORDER_RESPONSE | jq -r '.order_id')

# 5. 获取订单详情
echo -e "\n5. 测试获取订单详情..."
curl -X GET "${GATEWAY_URL}/api/v1/orders/${ORDER_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | jq .

echo -e "\n================================"
echo "测试 Feed Service API"
echo "================================"

# 6. 创建动态
echo -e "\n6. 测试创建动态..."
FEED_RESPONSE=$(curl -s -X POST "${GATEWAY_URL}/api/v1/feeds" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{
    \"user_id\": ${USER_ID},
    \"content\": \"这是一条测试动态！🎉\",
    \"images\": [
      \"https://example.com/image1.jpg\",
      \"https://example.com/image2.jpg\"
    ],
    \"location\": \"北京市朝阳区\"
  }")
echo $FEED_RESPONSE | jq .

FEED_ID=$(echo $FEED_RESPONSE | jq -r '.feed_id')

# 7. 获取动态详情
echo -e "\n7. 测试获取动态详情..."
curl -X GET "${GATEWAY_URL}/api/v1/feeds/${FEED_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | jq .

echo -e "\n================================"
echo "测试完成！"
echo "================================"
