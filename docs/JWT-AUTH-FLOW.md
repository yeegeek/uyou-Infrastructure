# JWT 认证流程详解

本文档详细说明 APISIX JWT 认证的工作原理，以及微服务如何获取用户信息。

## consumer_key 的含义

### 什么是 consumer_key？

`consumer_key` 是 **APISIX Consumer 的标识符**，用于匹配 JWT token 中的 `key` 字段。它**不是传递给微服务的 key**，而是 APISIX 内部用于识别和验证 JWT token 的标识符。

### 工作流程

```
1. 创建 Consumer（在 APISIX 中）
   consumer_key = "user_key"
   secret = "your-secret-key"
   
2. 用户登录（在微服务中）
   微服务生成 JWT token，payload 必须包含：
   {
     "key": "user_key",  // 必须匹配 Consumer 的 key
     "user_id": 123,
     "username": "testuser",
     "exp": 1234567890
   }
   
3. 客户端携带 Token 访问
   Authorization: Bearer <jwt-token>
   
4. APISIX 验证 Token
   - 提取 token payload 中的 "key" 字段
   - 查找 key="user_key" 的 Consumer
   - 使用该 Consumer 的 secret 验证 token 签名
   - 验证通过后，将用户信息添加到 HTTP Header
   
5. APISIX 转发请求到微服务
   - HTTP Header → gRPC metadata（自动转换）
   - 微服务从 metadata 中获取用户信息
```

## JWT Token 结构要求

### Token Payload 必须包含的字段

根据 APISIX 的要求，JWT token 的 payload **必须包含 `key` 字段**，且这个 key 必须匹配 Consumer 中配置的 key：

```json
{
  "key": "user_key",        // 必须！匹配 Consumer 的 key
  "user_id": 123,          // 自定义字段：用户 ID
  "username": "testuser",  // 自定义字段：用户名
  "exp": 1735689600        // 过期时间（可选，但推荐）
}
```

### 微服务生成 JWT Token 的示例

```go
package main

import (
    "time"
    "github.com/golang-jwt/jwt/v5"
)

// 生成 JWT Token（在用户登录时）
func generateJWTToken(userID int64, username string) (string, error) {
    // 从环境变量获取 secret（必须与 APISIX Consumer 的 secret 一致）
    secret := os.Getenv("APISIX_JWT_SECRET")
    if secret == "" {
        secret = "your-secret-key-change-in-production"
    }
    
    // 创建 token claims
    claims := jwt.MapClaims{
        "key":      "user_key",  // 必须！匹配 APISIX Consumer 的 key
        "user_id":  userID,      // 自定义：用户 ID
        "username": username,    // 自定义：用户名
        "exp":      time.Now().Add(7 * 24 * time.Hour).Unix(), // 7 天过期
    }
    
    // 创建 token
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    
    // 签名 token（使用与 APISIX Consumer 相同的 secret）
    tokenString, err := token.SignedString([]byte(secret))
    if err != nil {
        return "", err
    }
    
    return tokenString, nil
}

// 在 Login 方法中使用
func (s *UserService) Login(ctx context.Context, req *pb.LoginRequest) (*pb.LoginResponse, error) {
    // 验证用户名和密码
    user, err := s.validateUser(req.Username, req.Password)
    if err != nil {
        return nil, err
    }
    
    // 生成 JWT token
    token, err := generateJWTToken(user.ID, user.Username)
    if err != nil {
        return nil, err
    }
    
    return &pb.LoginResponse{
        Token:    token,
        UserId:   user.ID,
        Username: user.Username,
    }, nil
}
```

## 微服务如何获取用户信息

### 方式 1：从 gRPC Metadata 中获取（推荐）

APISIX 验证 JWT 后，会将用户信息添加到 HTTP Header 中，然后转换为 gRPC metadata。微服务可以从 metadata 中获取：

```go
package main

import (
    "context"
    "google.golang.org/grpc"
    "google.golang.org/grpc/metadata"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
)

// 从 gRPC metadata 中提取用户信息
func getUserFromContext(ctx context.Context) (int64, string, error) {
    // 获取 metadata
    md, ok := metadata.FromIncomingContext(ctx)
    if !ok {
        return 0, "", status.Error(codes.Unauthenticated, "missing metadata")
    }
    
    // APISIX 会将 HTTP Header 转换为 gRPC metadata
    // Header 名称会转换为小写，连字符变为下划线
    // X-Consumer-Username → x-consumer-username
    
    // 获取用户名（APISIX 自动添加）
    usernames := md.Get("x-consumer-username")
    if len(usernames) == 0 {
        return 0, "", status.Error(codes.Unauthenticated, "missing consumer username")
    }
    username := usernames[0]
    
    // 如果需要用户 ID，可以从 JWT token payload 中解析
    // 或者从数据库查询
    userID, err := getUserIDByUsername(username)
    if err != nil {
        return 0, "", status.Error(codes.Internal, "failed to get user ID")
    }
    
    return userID, username, nil
}

// 在 gRPC 方法中使用
func (s *UserService) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.GetUserResponse, error) {
    // 从 context 中获取当前用户信息
    currentUserID, currentUsername, err := getUserFromContext(ctx)
    if err != nil {
        return nil, err
    }
    
    // 验证权限（例如：只能查看自己的信息，或管理员可以查看所有）
    if req.UserId != currentUserID {
        // 可以添加权限检查逻辑
        // return nil, status.Error(codes.PermissionDenied, "cannot access other user's data")
    }
    
    // 查询用户信息
    user, err := s.getUserByID(req.UserId)
    if err != nil {
        return nil, err
    }
    
    return &pb.GetUserResponse{
        UserId:   user.ID,
        Username: user.Username,
        Email:    user.Email,
        Avatar:   user.Avatar,
    }, nil
}
```

### 方式 2：从 JWT Token 中解析用户信息

如果需要在微服务中解析 JWT token 获取更多信息（如 user_id），可以从 metadata 中获取原始 token：

```go
package main

import (
    "strings"
    "github.com/golang-jwt/jwt/v5"
)

// 从 metadata 中提取并解析 JWT token
func parseJWTFromContext(ctx context.Context) (jwt.MapClaims, error) {
    md, ok := metadata.FromIncomingContext(ctx)
    if !ok {
        return nil, status.Error(codes.Unauthenticated, "missing metadata")
    }
    
    // 获取 Authorization header（APISIX 会保留）
    authHeaders := md.Get("authorization")
    if len(authHeaders) == 0 {
        return nil, status.Error(codes.Unauthenticated, "missing authorization header")
    }
    
    // 提取 Bearer token
    authHeader := authHeaders[0]
    if !strings.HasPrefix(authHeader, "Bearer ") {
        return nil, status.Error(codes.Unauthenticated, "invalid authorization format")
    }
    
    tokenString := strings.TrimPrefix(authHeader, "Bearer ")
    
    // 解析 JWT token
    secret := os.Getenv("APISIX_JWT_SECRET")
    if secret == "" {
        secret = "your-secret-key-change-in-production"
    }
    
    token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
        if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, status.Error(codes.Unauthenticated, "invalid token algorithm")
        }
        return []byte(secret), nil
    })
    
    if err != nil {
        return nil, status.Error(codes.Unauthenticated, "invalid token")
    }
    
    if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
        return claims, nil
    }
    
    return nil, status.Error(codes.Unauthenticated, "invalid token claims")
}

// 使用示例
func (s *UserService) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.GetUserResponse, error) {
    // 解析 JWT token 获取用户信息
    claims, err := parseJWTFromContext(ctx)
    if err != nil {
        return nil, err
    }
    
    // 从 claims 中获取用户 ID
    userIDFloat, ok := claims["user_id"].(float64)
    if !ok {
        return nil, status.Error(codes.Internal, "invalid user_id in token")
    }
    userID := int64(userIDFloat)
    
    // 获取用户名
    username, _ := claims["username"].(string)
    
    // 使用获取到的信息进行业务处理
    // ...
}
```

## APISIX 自动添加的 Header

当 JWT 认证成功后，APISIX 会自动添加以下 HTTP Header（转换为 gRPC metadata）：

| HTTP Header | gRPC Metadata Key | 说明 |
|------------|-------------------|------|
| `X-Consumer-Username` | `x-consumer-username` | Consumer 的 username（即 "user_key"） |
| `X-Credential-Identifier` | `x-credential-identifier` | Credential 的 ID |
| `Authorization` | `authorization` | 原始 JWT token（如果 hide_credentials=false） |

**注意**：这些 Header 是 APISIX 添加的，不是从 JWT token payload 中提取的。如果需要用户的实际信息（如 user_id），需要：

1. **方式 A**：在 JWT token payload 中包含这些信息（推荐）
2. **方式 B**：在微服务中解析 JWT token 获取
3. **方式 C**：使用 `X-Consumer-Username` 查询数据库获取用户信息

## 完整示例

### 1. 用户服务生成 JWT Token

```go
// services/user/main.go
func (s *UserService) Login(ctx context.Context, req *pb.LoginRequest) (*pb.LoginResponse, error) {
    // 验证用户
    user, err := s.validateUser(req.Username, req.Password)
    if err != nil {
        return nil, err
    }
    
    // 生成 JWT token（必须包含 key 字段）
    token, err := generateJWTToken(user.ID, user.Username)
    if err != nil {
        return nil, err
    }
    
    return &pb.LoginResponse{
        Token:    token,
        UserId:   user.ID,
        Username: user.Username,
    }, nil
}

func generateJWTToken(userID int64, username string) (string, error) {
    secret := os.Getenv("APISIX_JWT_SECRET")
    if secret == "" {
        secret = "your-secret-key-change-in-production"
    }
    
    claims := jwt.MapClaims{
        "key":      "user_key",  // 必须匹配 APISIX Consumer 的 key
        "user_id":  userID,      // 用户 ID
        "username": username,    // 用户名
        "exp":      time.Now().Add(7 * 24 * time.Hour).Unix(),
    }
    
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString([]byte(secret))
}
```

### 2. 订单服务获取当前用户信息

```go
// services/order/main.go
func (s *OrderService) CreateOrder(ctx context.Context, req *pb.CreateOrderRequest) (*pb.CreateOrderResponse, error) {
    // 从 context 中获取当前用户信息
    currentUserID, _, err := getUserFromContext(ctx)
    if err != nil {
        return nil, err
    }
    
    // 验证：只能为自己创建订单
    if req.UserId != currentUserID {
        return nil, status.Error(codes.PermissionDenied, "cannot create order for other users")
    }
    
    // 创建订单
    order, err := s.createOrder(currentUserID, req.Items, req.TotalAmount)
    if err != nil {
        return nil, err
    }
    
    return &pb.CreateOrderResponse{
        OrderId:  order.ID,
        OrderNo:  order.OrderNo,
        Message:  "Order created successfully",
    }, nil
}

func getUserFromContext(ctx context.Context) (int64, string, error) {
    // 方式 1：从 metadata 中解析 JWT token（推荐）
    claims, err := parseJWTFromContext(ctx)
    if err != nil {
        return 0, "", err
    }
    
    userIDFloat, ok := claims["user_id"].(float64)
    if !ok {
        return 0, "", status.Error(codes.Internal, "invalid user_id in token")
    }
    
    username, _ := claims["username"].(string)
    return int64(userIDFloat), username, nil
}
```

## 配置要点

### 1. JWT Secret 必须一致

- **APISIX Consumer** 的 `secret` 必须与**微服务生成 JWT** 时使用的 `secret` 一致
- 通过环境变量 `APISIX_JWT_SECRET` 统一管理

### 2. JWT Token Payload 必须包含 key

- Token payload 中**必须包含 `"key": "user_key"`** 字段
- 这个 key 必须匹配 Consumer 中配置的 key

### 3. 微服务获取用户信息的方式

- **推荐**：从 JWT token payload 中解析（包含完整的用户信息）
- **备选**：从 `X-Consumer-Username` header 查询数据库

## 常见问题

### Q: consumer_key 是传递给微服务的吗？

**A:** 不是。`consumer_key` 是 APISIX 内部用于匹配 JWT token 的标识符。微服务不需要知道这个 key，只需要在生成 JWT token 时，在 payload 中包含 `"key": "user_key"` 即可。

### Q: 微服务如何知道当前是哪个用户？

**A:** 有两种方式：
1. **从 JWT token 解析**：从 `Authorization` header 中提取 token 并解析，获取 payload 中的 `user_id`、`username` 等信息
2. **从 APISIX Header 查询**：使用 `X-Consumer-Username` 查询数据库获取用户信息

### Q: 为什么 JWT token payload 必须包含 key 字段？

**A:** 这是 APISIX 的要求。APISIX 使用 token payload 中的 `key` 字段来查找对应的 Consumer，然后使用该 Consumer 的 `secret` 来验证 token 签名。

### Q: 微服务需要验证 JWT token 吗？

**A:** 通常不需要。APISIX 已经验证了 token 的有效性，微服务可以直接信任。但如果需要获取 token 中的用户信息，需要解析 token（使用相同的 secret）。

## 相关文档

- [APISIX JWT Auth 插件文档](https://apisix.apache.org/docs/apisix/next/plugins/jwt-auth/)
- [接口分离设计](./INTERFACE-SEPARATION.md) - 了解公共接口和内部接口的区别
