# consumer_key (user_key) 的作用详解

## 问题：为什么需要 `user_key`？

很多开发者会困惑：为什么 JWT token 的 payload 中必须包含 `"key": "user_key"` 字段？这个字段是做什么用的？

## 简单回答

`user_key` 是 **APISIX 用来查找 Consumer 的标识符**，不是传递给微服务的用户信息。

## 详细解释

### 1. APISIX 的 Consumer 机制

APISIX 使用 **Consumer** 来管理认证配置。每个 Consumer 可以配置不同的认证方式（如 JWT、API Key 等）。

```bash
# 在 APISIX 中创建 Consumer
PUT /apisix/admin/consumers/user_key
{
  "username": "user_key",
  "plugins": {
    "jwt-auth": {
      "key": "user_key",        # ← 这是 Consumer 的 key
      "secret": "your-secret",  # ← 这是用来验证 token 签名的 secret
      "algorithm": "HS256"
    }
  }
}
```

### 2. JWT Token 验证流程

当客户端携带 JWT token 访问 APISIX 时，APISIX 的验证流程是：

```
1. 客户端发送请求
   Authorization: Bearer <jwt-token>

2. APISIX 解析 JWT token，提取 payload
   {
     "key": "user_key",  ← APISIX 读取这个字段
     "user_id": 123,
     "username": "test",
     "exp": 1234567890
   }

3. APISIX 使用 payload 中的 "key" 字段查找 Consumer
   - 查找 key="user_key" 的 Consumer
   - 找到后，使用该 Consumer 的 secret 验证 token 签名

4. 验证通过后，APISIX 转发请求到微服务
   - 添加 X-Consumer-Username header（值为 "user_key"）
   - 保留原始 Authorization header（包含完整 token）
```

### 3. 为什么需要 `key` 字段？

**因为 APISIX 需要知道用哪个 Consumer 的 secret 来验证 token！**

- APISIX 可能配置了多个 Consumer（不同的 key 和 secret）
- 不同的 Consumer 可能使用不同的 secret
- APISIX 必须知道用哪个 secret 来验证 token

**解决方案**：在 JWT token payload 中包含 `key` 字段，告诉 APISIX 使用哪个 Consumer。

### 4. 完整示例

#### 步骤 1：创建 Consumer（在 APISIX 中）

```bash
# scripts/merge-apisix-configs.sh:179
consumer_key="user_key"
secret="your-secret-key-change-in-production"

curl -X PUT http://localhost:9180/apisix/admin/consumers/user_key \
  -H "X-API-KEY: <admin-key>" \
  -d '{
    "username": "user_key",
    "plugins": {
      "jwt-auth": {
        "key": "user_key",
        "secret": "your-secret-key-change-in-production",
        "algorithm": "HS256"
      }
    }
  }'
```

#### 步骤 2：生成 JWT Token（在微服务中）

```go
// services/user/main.go
token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
    "key":      "user_key",  // ← 必须！告诉 APISIX 使用 key="user_key" 的 Consumer
    "user_id":  123,         // ← 自定义字段：用户 ID（微服务使用）
    "username": "test",      // ← 自定义字段：用户名（微服务使用）
    "exp":      time.Now().Add(7 * 24 * time.Hour).Unix(),
})

// 使用与 Consumer 相同的 secret 签名
secret := os.Getenv("APISIX_JWT_SECRET")  // 必须与 Consumer 的 secret 一致
tokenString, _ := token.SignedString([]byte(secret))
```

#### 步骤 3：APISIX 验证 Token

```
客户端 → APISIX
Authorization: Bearer <token>

APISIX:
1. 解析 token payload，看到 "key": "user_key"
2. 查找 key="user_key" 的 Consumer
3. 使用该 Consumer 的 secret 验证 token 签名
4. 验证通过，转发请求到微服务
```

#### 步骤 4：微服务获取用户信息

```go
// 微服务从 gRPC metadata 中获取 JWT token
md, _ := metadata.FromIncomingContext(ctx)
authHeader := md.Get("authorization")[0]  // "Bearer <token>"

// 解析 token 获取用户信息
tokenString := strings.TrimPrefix(authHeader, "Bearer ")
token, _ := jwt.Parse(tokenString, ...)
claims := token.Claims.(jwt.MapClaims)

userID := int64(claims["user_id"].(float64))  // 从 token 中获取
username := claims["username"].(string)     // 从 token 中获取
```

## 关键要点

### 1. `user_key` 不是用户信息

- `user_key` 是 **APISIX Consumer 的标识符**
- 不是实际用户名，不是用户 ID
- 只是告诉 APISIX "使用哪个 Consumer 来验证这个 token"

### 2. 实际用户信息在 token payload 中

- `user_id`：实际用户 ID（微服务使用）
- `username`：实际用户名（微服务使用）
- 这些是自定义字段，微服务从 token 中解析获取

### 3. Secret 必须一致

- **APISIX Consumer 的 secret** 必须与 **微服务生成 token 时使用的 secret** 一致
- 都通过 `APISIX_JWT_SECRET` 环境变量配置

## 常见误解

### ❌ 误解 1：`user_key` 是传递给微服务的

**错误理解**：`user_key` 是传递给微服务的用户标识符

**正确理解**：`user_key` 是 APISIX 内部使用的 Consumer 标识符，微服务不需要知道它。微服务从 token payload 中获取实际的用户信息（`user_id`, `username`）。

### ❌ 误解 2：`user_key` 是用户名

**错误理解**：`user_key` 就是用户名

**正确理解**：`user_key` 是固定的 Consumer 标识符（所有用户都用同一个），实际用户名在 token payload 的 `username` 字段中。

### ❌ 误解 3：每个用户需要一个 Consumer

**错误理解**：每个用户需要创建一个 Consumer，key 就是用户 ID

**正确理解**：所有用户共享一个 Consumer（`user_key`），用户信息存储在 JWT token payload 中。

## 代码对比

### ❌ 错误：缺少 `key` 字段

```go
// 错误：缺少 "key" 字段，APISIX 无法找到对应的 Consumer
token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
    "user_id":  123,
    "username": "test",
    "exp":      time.Now().Add(7 * 24 * time.Hour).Unix(),
})
// 结果：APISIX 验证失败，返回 401 Unauthorized
```

### ✅ 正确：包含 `key` 字段

```go
// 正确：包含 "key" 字段，APISIX 可以找到对应的 Consumer
token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
    "key":      "user_key",  // ← 必须！告诉 APISIX 使用哪个 Consumer
    "user_id":  123,         // ← 实际用户 ID（微服务使用）
    "username": "test",      // ← 实际用户名（微服务使用）
    "exp":      time.Now().Add(7 * 24 * time.Hour).Unix(),
})
// 结果：APISIX 验证成功，转发请求到微服务
```

## 总结

| 字段 | 作用 | 使用者 | 说明 |
|------|------|--------|------|
| `key: "user_key"` | 告诉 APISIX 使用哪个 Consumer | APISIX | 必须包含，固定值 |
| `user_id` | 实际用户 ID | 微服务 | 自定义字段，从 token 解析 |
| `username` | 实际用户名 | 微服务 | 自定义字段，从 token 解析 |
| `exp` | Token 过期时间 | APISIX + 微服务 | 可选但推荐 |

## 相关文档

- [JWT 认证流程](./JWT-AUTH-FLOW.md) - 完整的 JWT 认证流程
- [微服务 JWT 处理示例](../examples/auth/microservice_jwt_handler.go) - 代码示例
