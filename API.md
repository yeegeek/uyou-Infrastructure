# API 接口文档

所有 API 通过 APISIX Gateway 访问，基础 URL: `http://localhost:9080`

## User Service API

### 1. 用户注册

**接口**: `POST /api/v1/users/register`

**请求体**:
```json
{
  "username": "string",
  "email": "string",
  "password": "string"
}
```

**响应**:
```json
{
  "user_id": 1,
  "message": "User registered successfully"
}
```

**示例**:
```bash
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'
```

---

### 2. 用户登录

**接口**: `POST /api/v1/users/login`

**请求体**:
```json
{
  "username": "string",
  "password": "string"
}
```

**响应**:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user_id": 1,
  "username": "testuser"
}
```

**示例**:
```bash
curl -X POST http://localhost:9080/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "password123"
  }'
```

---

### 3. 获取用户信息

**接口**: `GET /api/v1/users/{user_id}`

**路径参数**:
- `user_id`: 用户ID

**响应**:
```json
{
  "user_id": 1,
  "username": "testuser",
  "email": "test@example.com",
  "avatar": "https://example.com/avatar.jpg",
  "created_at": "2026-01-22T10:30:00Z"
}
```

**示例**:
```bash
curl -X GET http://localhost:9080/api/v1/users/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## Order Service API

### 1. 创建订单

**接口**: `POST /api/v1/orders`

**请求体**:
```json
{
  "user_id": 1,
  "items": [
    {
      "product_id": 1001,
      "product_name": "商品名称",
      "quantity": 2,
      "price": 99.99
    }
  ],
  "total_amount": 199.98
}
```

**响应**:
```json
{
  "order_id": 1,
  "order_no": "ORD1737520800001",
  "message": "Order created successfully"
}
```

**示例**:
```bash
curl -X POST http://localhost:9080/api/v1/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "user_id": 1,
    "items": [
      {
        "product_id": 1001,
        "product_name": "测试商品",
        "quantity": 2,
        "price": 99.99
      }
    ],
    "total_amount": 199.98
  }'
```

---

### 2. 获取订单详情

**接口**: `GET /api/v1/orders/{order_id}`

**路径参数**:
- `order_id`: 订单ID

**响应**:
```json
{
  "order_id": 1,
  "order_no": "ORD1737520800001",
  "user_id": 1,
  "items": [
    {
      "product_id": 1001,
      "product_name": "测试商品",
      "quantity": 2,
      "price": 99.99
    }
  ],
  "total_amount": 199.98,
  "status": "pending",
  "created_at": "2026-01-22T10:30:00Z"
}
```

**示例**:
```bash
curl -X GET http://localhost:9080/api/v1/orders/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## Feed Service API

### 1. 创建动态

**接口**: `POST /api/v1/feeds`

**请求体**:
```json
{
  "user_id": 1,
  "content": "动态内容",
  "images": [
    "https://example.com/image1.jpg",
    "https://example.com/image2.jpg"
  ],
  "location": "北京市朝阳区"
}
```

**响应**:
```json
{
  "feed_id": "65b8f9e7c1234567890abcde",
  "message": "Feed created successfully"
}
```

**示例**:
```bash
curl -X POST http://localhost:9080/api/v1/feeds \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "user_id": 1,
    "content": "这是一条测试动态",
    "images": ["https://example.com/image.jpg"],
    "location": "北京"
  }'
```

---

### 2. 获取动态详情

**接口**: `GET /api/v1/feeds/{feed_id}`

**路径参数**:
- `feed_id`: 动态ID (MongoDB ObjectID)

**响应**:
```json
{
  "feed_id": "65b8f9e7c1234567890abcde",
  "user_id": 1,
  "content": "这是一条测试动态",
  "images": ["https://example.com/image.jpg"],
  "location": "北京",
  "likes": 10,
  "comments": 5,
  "created_at": "2026-01-22T10:30:00Z"
}
```

**示例**:
```bash
curl -X GET http://localhost:9080/api/v1/feeds/65b8f9e7c1234567890abcde \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## 错误码

| HTTP 状态码 | 说明 |
|------------|------|
| 200 | 请求成功 |
| 400 | 请求参数错误 |
| 401 | 未授权（Token 无效或过期）|
| 404 | 资源不存在 |
| 429 | 请求过于频繁（触发限流）|
| 500 | 服务器内部错误 |
| 502 | 网关错误（后端服务不可用）|

## 限流策略

| 接口 | 限制 |
|------|------|
| `/api/v1/users/register` | 100 次/分钟 |
| `/api/v1/users/login` | 50 次/分钟 |
| `/api/v1/orders` | 50 次/分钟 |
| `/api/v1/feeds` | 100 次/分钟 |
| 其他接口 | 无限制 |

## 认证说明

### JWT Token

登录成功后会返回 JWT Token，后续请求需要在 Header 中携带：

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Token 有效期

- 默认有效期: 7 天
- 过期后需要重新登录

## 测试工具

### 使用 cURL

```bash
# 设置变量
TOKEN="your_jwt_token"
USER_ID=1

# 测试请求
curl -X GET http://localhost:9080/api/v1/users/${USER_ID} \
  -H "Authorization: Bearer ${TOKEN}"
```

### 使用 Postman

1. 导入 API 集合
2. 设置环境变量 `base_url` = `http://localhost:9080`
3. 登录后保存 `token` 到环境变量
4. 在请求 Header 中使用 `{{token}}`

### 使用测试脚本

```bash
./scripts/test-api.sh
```

## gRPC 直接调用

如果需要直接测试 gRPC 服务（绕过 APISIX）：

```bash
# 安装 grpcurl
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# 查看服务列表
grpcurl -plaintext localhost:50051 list

# 调用方法
grpcurl -plaintext -d '{"username":"test","password":"123"}' \
  localhost:50051 user.UserService/Login
```

## 性能基准

在标准配置下（4核8G）：

| 服务 | QPS | 平均延迟 |
|------|-----|---------|
| User Service | ~5000 | 20ms |
| Order Service | ~3000 | 35ms |
| Feed Service | ~8000 | 15ms |

*注：实际性能取决于硬件配置和网络环境*
