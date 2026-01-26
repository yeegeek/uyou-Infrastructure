# 公共接口 vs 内部接口分离设计

本文档说明如何区分和实现公共接口（通过 APISIX 暴露）和内部接口（直接 gRPC 调用）。

## 概述

在微服务架构中，接口可以分为两类：

1. **公共接口**：通过 APISIX 网关暴露，供客户端（Web、移动端等）调用
   - 使用 JWT 认证
   - 支持 REST to gRPC 转码
   - 通过 HTTP/JSON 访问

2. **内部接口**：不通过 APISIX，供其他微服务直接调用
   - 直接 gRPC 调用
   - 不暴露在公网
   - 依赖内网安全（无需额外认证）

## 设计原则

### 公共接口

- **访问方式**：`http://gateway:9080/api/v1/...`
- **认证方式**：JWT Token（在 HTTP Header 中）
- **协议转换**：REST/JSON → gRPC（由 APISIX 处理）
- **用途**：客户端访问、用户操作
- **示例**：用户注册、登录、创建订单、查看动态

### 内部接口

- **访问方式**：`grpc://service:port`（直接连接）
- **认证方式**：依赖内网安全（无需额外认证）
- **协议**：纯 gRPC
- **用途**：服务间调用、批量操作、管理功能
- **示例**：批量获取用户信息、验证用户权限、获取统计信息

## 实现方式

### 1. Proto 文件分离

使用不同的 proto 文件定义公共接口和内部接口：

#### 公共接口 Proto（user.proto）

```protobuf
syntax = "proto3";

package user;

option go_package = "github.com/your-org/user-service/proto/user";

// 公共接口：通过 APISIX 暴露，使用 JWT 认证
service UserService {
  // 用户注册（公开接口）
  rpc Register(RegisterRequest) returns (RegisterResponse);
  
  // 用户登录（公开接口，返回 JWT token）
  rpc Login(LoginRequest) returns (LoginResponse);
  
  // 获取用户信息（受保护接口，需要 JWT）
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  
  // 更新用户信息（受保护接口，需要 JWT）
  rpc UpdateUser(UpdateUserRequest) returns (UpdateUserResponse);
}

// 消息定义...
message RegisterRequest {
  string username = 1;
  string email = 2;
  string password = 3;
}

message RegisterResponse {
  int64 user_id = 1;
  string message = 2;
}

// ... 其他消息定义
```

#### 内部接口 Proto（user-internal.proto）

```protobuf
syntax = "proto3";

package user;

option go_package = "github.com/your-org/user-service/proto/user";

// 内部接口：不通过 APISIX，直接 gRPC 调用（内网安全）
service UserInternalService {
  // 批量获取用户信息（内部接口，供其他微服务调用）
  rpc BatchGetUsers(BatchGetUsersRequest) returns (BatchGetUsersResponse);
  
  // 验证用户权限（内部接口，供其他微服务调用）
  rpc ValidateUserPermission(ValidateUserPermissionRequest) returns (ValidateUserPermissionResponse);
  
  // 获取用户统计信息（内部接口，供管理服务调用）
  rpc GetUserStats(GetUserStatsRequest) returns (GetUserStatsResponse);
}

// 消息定义...
message BatchGetUsersRequest {
  repeated int64 user_ids = 1;
}

message BatchGetUsersResponse {
  repeated UserInfo users = 1;
}

message UserInfo {
  int64 user_id = 1;
  string username = 2;
  string email = 3;
}

// ... 其他消息定义
```

### 2. 目录结构

```
services/
  user/
    proto/
      user.proto              # 公共接口（通过 APISIX）
      user-internal.proto     # 内部接口（直接 gRPC）
    main.go
  order/
    proto/
      order.proto
      order-internal.proto
    main.go
  feed/
    proto/
      feed.proto
      feed-internal.proto
    main.go
```

### 3. 服务端实现

在同一个 gRPC 服务器中注册两个服务：

```go
package main

import (
    "net"
    "google.golang.org/grpc"
    pb "github.com/your-org/user-service/proto/user"
)

func main() {
    // 创建 gRPC 服务器
    s := grpc.NewServer()

    // 注册公共接口服务（通过 APISIX 调用）
    // 这些接口已经通过 APISIX 的 JWT 认证
    pb.RegisterUserServiceServer(s, &userService{})

    // 注册内部接口服务（直接 gRPC 调用）
    // 这些接口依赖内网安全，无需额外认证
    pb.RegisterUserInternalServiceServer(s, &userInternalService{})

    // 监听端口
    lis, err := net.Listen("tcp", ":50051")
    if err != nil {
        log.Fatalf("failed to listen: %v", err)
    }
    
    if err := s.Serve(lis); err != nil {
        log.Fatalf("failed to serve: %v", err)
    }
}
```

### 4. 路由配置

**只配置公共接口**，内部接口不配置：

```yaml
# apisix/config/routes/user-routes.yaml
# 注意：只包含公共接口，内部接口不在这里配置

routes:
  - name: user-register
    uri: /api/v1/users/register
    methods: [POST]
    # ... 配置（无 jwt-auth，公开接口）

  - name: user-login
    uri: /api/v1/users/login
    methods: [POST]
    # ... 配置（无 jwt-auth，公开接口）

  - name: user-getuser
    uri: /api/v1/users/*
    methods: [GET]
    plugins:
      jwt-auth: {}  # 需要 JWT
      # ... 其他配置

  # 注意：内部接口（如 BatchGetUsers）不在这里配置
  # 它们只能通过直接 gRPC 调用访问
```

### 5. 微服务间调用内部接口

```go
// order-service 调用 user-service 的内部接口
package main

import (
    "context"
    "os"
    "google.golang.org/grpc"
    "google.golang.org/grpc/metadata"
    userpb "github.com/your-org/user-service/proto/user"
)

func getUsersForOrder(ctx context.Context, userIDs []int64) ([]*userpb.UserInfo, error) {
    // 创建到 user-service 的连接（直接连接，不通过 APISIX）
    conn, err := grpc.Dial("user-service:50051", grpc.WithInsecure())
    if err != nil {
        return nil, err
    }
    defer conn.Close()

    // 创建内部接口客户端
    client := userpb.NewUserInternalServiceClient(conn)

    // 直接调用内部接口（内网安全，无需 API Key）
    resp, err := client.BatchGetUsers(ctx, &userpb.BatchGetUsersRequest{
        UserIds: userIDs,
    })
    if err != nil {
        return nil, err
    }

    return resp.Users, nil
}
```

## 完整工作流程示例

### 场景：用户创建订单

```
1. 客户端 → APISIX（JWT 认证）
   POST /api/v1/orders
   Authorization: Bearer <jwt-token>
   {
     "user_id": 1,
     "items": [...],
     "total_amount": 99.99
   }

2. APISIX 验证 JWT token
   ✓ Token 有效 → 继续
   ✗ Token 无效 → 返回 401

3. APISIX → Order Service（gRPC，通过 APISIX 转码）
   APISIX 将 JSON 转换为 gRPC 格式
   调用: order.OrderService.CreateOrder

4. Order Service 处理订单
   需要验证用户信息 → 调用 User Service

5. Order Service → User Service（直接 gRPC，内网安全）
   调用: user.UserInternalService.BatchGetUsers
   
6. User Service 处理请求
   返回用户信息

7. Order Service 继续处理
   使用用户信息创建订单
   返回订单结果

8. APISIX → 客户端
   APISIX 将 gRPC 响应转换为 JSON
   返回订单创建结果
```

## 接口分类指南

### 应该作为公共接口的接口

- 用户注册、登录
- 用户信息查询、更新
- 创建订单、查询订单
- 发布动态、查看动态
- 点赞、评论等用户操作

### 应该作为内部接口的接口

- 批量操作（批量获取用户、批量查询订单）
- 权限验证（验证用户权限、验证资源访问权限）
- 统计信息（用户统计、订单统计、系统统计）
- 管理功能（用户管理、系统配置）
- 数据同步（跨服务数据同步）

## 安全考虑

### 1. 网络隔离

- 内部服务应部署在私有网络
- 使用防火墙规则限制访问
- 避免将内部服务暴露到公网

### 2. 认证机制

- 公共接口：使用 JWT（包含用户身份信息）
- 内部接口：依赖内网安全（无需额外认证）

### 3. 访问控制

- 公共接口：通过 APISIX 进行限流、熔断
- 内部接口：依赖内网安全（VPC、防火墙规则）

### 4. 监控和日志

- 记录所有接口调用
- 监控异常访问模式
- 设置告警阈值

## 最佳实践

1. **明确接口分类**：在设计阶段就明确哪些是公共接口，哪些是内部接口
2. **使用不同的 proto 文件**：便于管理和维护
3. **统一命名规范**：内部接口使用 `*-internal.proto` 命名
4. **文档化**：为每个接口编写清晰的文档
5. **版本管理**：公共接口需要考虑向后兼容，内部接口可以更灵活

## 常见问题

### Q: 为什么内部接口不通过 APISIX？

**A:** 
- 减少网络跳转，提高性能
- 避免不必要的协议转换开销
- 更细粒度的安全控制
- 降低 APISIX 的负载

### Q: 如何判断一个接口应该是公共的还是内部的？

**A:** 
- 如果客户端（Web、移动端）需要调用 → 公共接口
- 如果只有其他微服务需要调用 → 内部接口
- 如果涉及批量操作、管理功能 → 内部接口

### Q: 内部接口可以暴露在 APISIX 上吗？

**A:** 可以，但不推荐。如果确实需要，应该：
- 使用不同的路由前缀（如 `/api/v1/internal/...`）
- 使用不同的认证机制（如 IP 白名单等）
- 限制访问来源（IP 白名单等）

### Q: 如何测试内部接口？

**A:** 
- 使用 `grpcurl` 工具直接调用
- 编写单元测试和集成测试
- 使用服务间测试框架

## 相关文档

- [README.md](../README.md) - 项目总体文档
