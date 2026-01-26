# API 接口参考文档

所有 API 通过 APISIX Gateway 访问，基础 URL: `http://localhost:9080`

## 认证说明

### JWT Token
登录成功后会返回 JWT Token，后续请求需要在 Header 中携带：
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 重要：`user_key` 字段
微服务生成的 JWT Payload **必须** 包含 `"key": "user_key"` 字段，否则 APISIX 无法识别 Consumer，导致认证失败。

---

## User Service API (用户服务)

### 1. 用户注册
- **接口**: `POST /api/v1/users/register`
- **认证**: 无需认证
- **请求体**:
```json
{
  "username": "testuser",
  "email": "test@example.com",
  "password": "password123"
}
```
- **响应**: `{"user_id": 1, "message": "User registered successfully"}`

### 2. 用户登录
- **接口**: `POST /api/v1/users/login`
- **请求体**: `{"username": "testuser", "password": "password123"}`
- **响应**: `{"token": "JWT_TOKEN", "user_id": 1, "username": "testuser"}`

---

## Order Service API (订单服务)

### 1. 创建订单
- **接口**: `POST /api/v1/orders`
- **认证**: 需要 JWT
- **请求体**:
```json
{
  "user_id": 1,
  "items": [{"product_id": 1001, "product_name": "测试商品", "quantity": 2, "price": 99.99}],
  "total_amount": 199.98
}
```

---

## Feed Service API (动态服务)

### 1. 创建动态
- **接口**: `POST /api/v1/feeds`
- **认证**: 需要 JWT
- **请求体**:
```json
{
  "user_id": 1,
  "content": "我的第一条动态！",
  "images": ["https://example.com/image.jpg"],
  "location": "北京"
}
```

---

## 错误码说明

| HTTP 状态码 | 说明 |
|------------|------|
| 200 | 请求成功 |
| 401 | 未授权（Token 无效或过期）|
| 502 | 网关错误（后端服务不可用）|

---

## 测试工具
运行测试脚本：`./scripts/test-api.sh`
