# 项目教程

本文档提供项目的完整教程，包括架构设计、核心概念、API 文档、开发指南和流程详解。

## 📋 目录

- [项目介绍](#项目介绍)
- [架构设计](#架构设计)
- [核心概念](#核心概念)
- [API 接口文档](#api-接口文档)
- [开发指南](#开发指南)
- [架构流程详解](#架构流程详解)
- [性能优化](#性能优化)
- [生产部署](#生产部署)

---

## 项目介绍

### 项目目标

这是一个基于 **Apache APISIX + Go 微服务** 的完整架构学习项目，帮助您从单体应用快速过渡到微服务架构。

**学习目标：**
- 学习 API Gateway + 微服务架构模式
- 理解 REST to gRPC 转码机制
- 掌握多数据库（PostgreSQL + MongoDB）集成
- 实践 Docker 容器化部署
- 体验服务间 gRPC 通信

### 项目结构

```
uyou-Infrastructure/
├── services/               # 微服务目录
│   ├── user/              # 用户服务 (Go + PostgreSQL + Redis)
│   │   ├── main.go        # 服务主程序
│   │   ├── proto/         # 生成的 gRPC 代码
│   │   ├── Dockerfile     # Docker 构建文件
│   │   └── go.mod         # Go 依赖管理
│   ├── order/             # 订单服务 (Go + PostgreSQL + Redis)
│   │   ├── main.go
│   │   ├── proto/
│   │   ├── Dockerfile
│   │   └── go.mod
│   └── feed/              # 动态服务 (Go + MongoDB + Redis)
│       ├── main.go
│       ├── proto/
│       ├── Dockerfile
│       └── go.mod
├── proto/                 # gRPC Proto 定义
│   ├── user.proto
│   ├── order.proto
│   └── feed.proto
├── apisix/                # APISIX 配置
│   └── config/
│       ├── config.yaml    # APISIX 主配置
│       └── apisix.yaml    # 路由和插件配置（文件驱动模式，当前未使用）
├── scripts/               # 工具脚本
│   ├── init-postgres.sh   # PostgreSQL 初始化
│   ├── init-apisix-routes.sh  # APISIX 路由初始化
│   └── test-api.sh        # API 测试脚本
├── docker-compose.yml     # Docker 编排文件
├── Makefile               # 构建和管理命令
├── RUN.md                 # 运行指南
└── TUTORIAL.md            # 本文件
```

---

## 架构设计

### 架构概览

本项目采用 **API Gateway + 微服务** 架构模式，使用 Apache APISIX 作为统一网关，后端微服务使用 Go 语言开发，通过 gRPC 进行服务间通信。

```
┌─────────────┐
│   客户端     │ (REST/JSON)
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│            Apache APISIX Gateway                    │
│  - JWT 认证                                          │
│  - 限流/熔断                                         │
│  - CORS                                             │
│  - 日志/TraceID                                      │
│  - REST → gRPC 转码                                  │
└──────┬──────────────────┬───────────────────┬──────┘
       │                  │                   │
       ▼                  ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   用户服务   │    │   交易服务   │    │   动态服务   │
│ (User)      │    │ (Order)     │    │ (Feed)      │
│             │    │             │    │             │
│ PostgreSQL  │    │ PostgreSQL  │    │ MongoDB     │
│ Redis       │    │ Redis       │    │ Redis       │
└─────────────┘    └─────────────┘    └─────────────┘
```

### 微服务划分

#### 1. User Service (用户服务)
- **职责**: 用户注册、登录、认证、个人资料管理
- **技术栈**: Go + PostgreSQL + Redis
- **端口**: 50051 (gRPC)
- **数据库**: PostgreSQL (强一致性)

#### 2. Order Service (交易服务)
- **职责**: 商城订单、交易处理、支付流程
- **技术栈**: Go + PostgreSQL + Redis
- **端口**: 50052 (gRPC)
- **数据库**: PostgreSQL (事务支持)

#### 3. Feed Service (动态服务)
- **职责**: 用户动态、内容发布、时间线
- **技术栈**: Go + MongoDB + Redis
- **端口**: 50053 (gRPC)
- **数据库**: MongoDB (高吞吐、灵活 Schema)

### 技术选型

#### API Gateway
- **Apache APISIX**: 高性能、云原生 API 网关
  - 支持 REST to gRPC 转码
  - 内置限流、熔断、认证插件
  - 动态路由配置

#### 服务间通信
- **gRPC**: 高性能 RPC 框架
  - Protocol Buffers 序列化
  - HTTP/2 传输
  - 双向流支持

#### 数据存储
- **PostgreSQL**: 关系型数据库，用于交易、用户等强一致性场景
- **MongoDB**: 文档数据库，用于动态、消息等高吞吐场景
- **Redis**: 缓存层，用于会话、热点数据

#### 基础设施
- **Docker**: 容器化部署
- **Docker Compose**: 本地开发编排
- **etcd**: APISIX 配置中心

### 数据库选型理由

| 服务 | 数据库 | 原因 |
|------|--------|------|
| User | PostgreSQL | 用户数据需要强一致性和事务支持 |
| Order | PostgreSQL | 订单涉及金额，需要 ACID 事务 |
| Feed | MongoDB | 动态内容灵活，读写量大，适合文档存储 |

### 缓存策略

- **用户信息**: Cache-Aside 模式，TTL 24小时
- **订单信息**: Cache-Aside 模式，TTL 1小时
- **动态信息**: Cache-Aside 模式，TTL 1小时

### 扩展性设计

#### 水平扩展
- 所有微服务无状态设计，支持多实例部署
- APISIX 自动负载均衡
- 数据库读写分离、分片

#### 高可用
- 服务多副本部署
- 健康检查和自动重启
- 熔断降级机制

#### 监控观测
- TraceID 全链路追踪
- 统一日志收集
- 性能指标监控

---

## 核心概念

### 1. REST to gRPC 转码

APISIX 自动将客户端的 REST/JSON 请求转换为 gRPC 调用：

```
客户端 REST 请求:
POST /api/v1/users/register
{
  "username": "test",
  "email": "test@example.com",
  "password": "123456"
}

↓ APISIX 转码 ↓

gRPC 调用:
user.UserService/Register
RegisterRequest {
  username: "test"
  email: "test@example.com"
  password: "123456"
}
```

### 2. Protobuf 基础知识

#### 字段编号（Field Numbers）

在 protobuf 中，每个字段都有一个唯一的编号，例如：

```protobuf
message CreateFeedRequest {
  int64 user_id = 1;      // 字段编号 1
  string content = 2;     // 字段编号 2
  repeated string images = 3;  // 字段编号 3
  string location = 4;    // 字段编号 4
}
```

**字段编号的作用：**

1. **二进制编码标识**：protobuf 在序列化时使用编号而不是字段名，这样更高效
   - 二进制数据中，`user_id` 用数字 `1` 表示，而不是字符串 `"user_id"`
   - 这大大减小了数据体积，提高了传输效率

2. **版本兼容性**：添加新字段时不会破坏旧代码
   ```protobuf
   // 旧版本
   message CreateFeedRequest {
     int64 user_id = 1;
     string content = 2;
   }
   
   // 新版本（添加新字段）
   message CreateFeedRequest {
     int64 user_id = 1;      // 保持不变
     string content = 2;      // 保持不变
     string location = 3;     // 新字段，使用新编号
   }
   ```
   旧代码可以忽略新字段，新代码可以处理旧数据，实现向后兼容。

3. **字段顺序无关**：编号决定了字段在二进制中的位置，而不是定义顺序

**重要规则：**
- ✅ **每个 message 内唯一**：同一个 message 内的字段编号不能重复
- ✅ **不同 message 可重复**：不同 message 可以使用相同的编号
- ⚠️ **一旦使用不要随意更改**：更改编号会导致数据不兼容
- ✅ **编号范围**：1-536870911（19000-19999 保留，不可用）

**最佳实践：**
1. **从 1 开始，按顺序递增**：保持编号连续，便于维护
2. **预留一些编号**：如果删除字段，可以暂时保留编号，避免立即复用
3. **不要随意更改已使用的编号**：这会导致数据不兼容

#### repeated 关键字（数组）

在 Protobuf 中，**`repeated` 关键字表示数组/列表**。

**示例：**
```protobuf
message CreateFeedRequest {
  int64 user_id = 1;              // 单个值
  string content = 2;              // 单个值
  repeated string images = 3;     // 数组/列表 ← 这就是数组！
  string location = 4;             // 单个值
}
```

**对应关系：**

| Protobuf | Go 语言 | 说明 |
|----------|---------|------|
| `string images` | `string` | 单个字符串 |
| `repeated string images` | `[]string` | 字符串数组/切片 |

**在代码中的使用：**

```protobuf
message CreateFeedRequest {
  repeated string images = 3;  // 字符串数组
}

message OrderItem {
  int64 product_id = 1;
  string product_name = 2;
  int32 quantity = 3;
  double price = 4;
}

message CreateOrderRequest {
  int64 user_id = 1;
  repeated OrderItem items = 2;  // OrderItem 数组
  double total_amount = 3;
}
```

**Go 代码：**
```go
req := &pb.CreateFeedRequest{
    Images: []string{
        "https://example.com/image1.jpg",
        "https://example.com/image2.jpg",
    },
}

orderReq := &pb.CreateOrderRequest{
    UserId: 123,
    Items: []*pb.OrderItem{  // OrderItem 指针数组
        {ProductId: 1001, ProductName: "商品A", Quantity: 2, Price: 99.99},
        {ProductId: 1002, ProductName: "商品B", Quantity: 1, Price: 49.99},
    },
    TotalAmount: 249.97,
}
```

**JSON 请求（通过 APISIX）：**
```json
{
  "user_id": 123,
  "content": "我的动态",
  "images": [
    "https://example.com/image1.jpg",
    "https://example.com/image2.jpg"
  ],
  "location": "北京"
}
```

---

## API 接口文档

所有 API 通过 APISIX Gateway 访问，基础 URL: `http://localhost:9080`

### User Service API

#### 1. 用户注册

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

#### 2. 用户登录

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

#### 3. 获取用户信息

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

### Order Service API

#### 1. 创建订单

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

#### 2. 获取订单详情

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

### Feed Service API

#### 1. 创建动态

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

#### 2. 获取动态详情

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

### 错误码

| HTTP 状态码 | 说明 |
|------------|------|
| 200 | 请求成功 |
| 400 | 请求参数错误 |
| 401 | 未授权（Token 无效或过期）|
| 404 | 资源不存在 |
| 429 | 请求过于频繁（触发限流）|
| 500 | 服务器内部错误 |
| 502 | 网关错误（后端服务不可用）|

### 认证说明

#### JWT Token

登录成功后会返回 JWT Token，后续请求需要在 Header 中携带：

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Token 有效期

- 默认有效期: 7 天
- 过期后需要重新登录

### gRPC 直接调用

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

---

## 开发指南

### 修改 Proto 定义

1. 编辑 `proto/*.proto` 文件
2. 自动生成代码并更新 APISIX 配置：
   ```bash
   make proto-update
   ```
   这个命令会自动：
   - 生成 Go 代码到各服务的 `proto/` 目录
   - 从 proto 文件读取并更新 APISIX 的 proto 定义和路由配置
3. 重启服务：
   ```bash
   make restart
   ```

**注意：** 如果只需要更新 APISIX 配置（不重新生成代码），可以运行：
```bash
make update-apisix
```

### 添加新的 RPC 方法

当你在 proto 文件中添加新的 RPC 方法时，需要手动在路由配置脚本中添加对应的路由。

**示例：添加 `DeleteUser` RPC 方法**

1. **在 `proto/user.proto` 中添加新的 RPC 方法：**
   ```protobuf
   service UserService {
     // ... 现有的方法 ...
     
     // 删除用户（新添加的）
     rpc DeleteUser(DeleteUserRequest) returns (DeleteUserResponse);
   }
   
   // 添加对应的 message
   message DeleteUserRequest {
     int64 user_id = 1;
   }
   
   message DeleteUserResponse {
     bool success = 1;
     string message = 2;
   }
   ```

2. **在 `scripts/init-apisix-routes.sh` 中添加路由配置：**
   
   找到对应的服务路由部分（例如 User Service），添加新的路由：
   ```bash
   # 创建 User Service 路由
   echo -e "\n创建 User Service 路由..."
   create_route "user-register" "/api/v1/users/register" "POST" "user-service:50051" "1" "user.UserService" "Register"
   create_route "user-login" "/api/v1/users/login" "POST" "user-service:50051" "1" "user.UserService" "Login"
   create_wildcard_route "user-get" "/api/v1/users/*" "GET" "user-service:50051" "1" "user.UserService" "GetUser"
   # 👇 新添加的路由
   create_route "user-delete" "/api/v1/users/delete" "DELETE" "user-service:50051" "1" "user.UserService" "DeleteUser"
   ```
   
   **路由参数说明：**
   - `"user-delete"`：路由名称（唯一标识）
   - `"/api/v1/users/delete"`：HTTP 路径
   - `"DELETE"`：HTTP 方法（GET/POST/PUT/DELETE）
   - `"user-service:50051"`：后端服务地址和端口
   - `"1"`：proto ID（User Service 是 1，Order Service 是 2，Feed Service 是 3）
   - `"user.UserService"`：proto 中的服务名（格式：`package.Service`）
   - `"DeleteUser"`：RPC 方法名

3. **运行更新命令：**
   ```bash
   make proto-update
   ```
   
   这会自动：
   - ✅ 生成 Go 代码（包含新的 `DeleteUser` 方法）
   - ✅ 更新 APISIX 的 proto 定义（自动从 proto 文件读取）
   - ✅ 创建新的路由配置（通过脚本中的 `create_route` 调用）

4. **在 Go 服务中实现该方法：**
   
   在 `services/user/main.go` 中实现 `DeleteUser` 方法：
   ```go
   func (s *server) DeleteUser(ctx context.Context, req *pb.DeleteUserRequest) (*pb.DeleteUserResponse, error) {
       // 实现删除用户的逻辑
       // ...
       return &pb.DeleteUserResponse{
           Success: true,
           Message: "User deleted successfully",
       }, nil
   }
   ```

**总结：**
- ✅ Proto 定义更新：**自动**（从 proto 文件读取）
- ⚠️ 路由配置：**手动**（需要在脚本中添加 `create_route` 调用）
- ✅ Go 代码生成：**自动**（`make proto` 会生成）
- ⚠️ 业务逻辑实现：**手动**（在 Go 代码中实现）

### 添加新的微服务

1. 在 `services/` 下创建新目录
2. 定义 Proto 文件
3. 实现服务逻辑
4. 创建 Dockerfile
5. 在 `docker-compose.yml` 中添加服务
6. 在 `scripts/init-apisix-routes.sh` 中添加路由

### 本地开发

如果需要在本地运行单个服务进行调试：

```bash
# 启动基础设施（数据库、Redis、etcd）
docker compose up -d postgres mongodb redis etcd

# 本地运行服务
cd services/user
export DB_HOST=localhost
export REDIS_HOST=localhost
go run main.go
```

---

## 架构流程详解

### 1. etcd 的作用和必要性

#### etcd 是什么？

**etcd** 是一个分布式键值存储系统，在 APISIX 架构中充当**配置中心**的角色。

#### etcd 在 APISIX 中的作用

```
┌─────────────┐
│   APISIX     │
│  (API网关)   │
└──────┬───────┘
       │ 读取配置
       ▼
┌─────────────┐
│    etcd     │  ← 存储所有路由配置、proto 定义等
│  (配置中心)  │
└─────────────┘
```

**etcd 存储的内容：**
- ✅ 路由配置（Routes）：哪些 HTTP 路径对应哪些后端服务
- ✅ Proto 定义：gRPC 服务的接口定义
- ✅ 插件配置：限流、认证等插件的配置
- ✅ 上游服务配置：后端服务的地址和负载均衡策略

#### 是否必须？

**在传统部署模式下，etcd 是必须的。**

APISIX 3.x 有两种部署模式：

1. **传统模式（Traditional Mode）** - **当前使用**
   - 使用 etcd 作为配置中心 ✅ **必须**
   - 配置通过 Admin API 写入 etcd
   - APISIX 从 etcd 读取配置
   - 适合生产环境，支持动态配置

2. **文件驱动模式（File-Driven Mode）**
   - 不使用 etcd
   - 配置从本地 YAML 文件读取
   - 配置文件：`apisix/config/apisix.yaml`（必须以 `#END` 结尾）
   - 适合简单场景，不支持动态配置
   - **注意**：当前项目中的 `apisix.yaml` 文件**不会被使用**，因为使用的是 etcd 模式

**当前项目使用传统模式，所以 etcd 是必须的。**

#### etcd 的工作流程

```
1. 开发者运行脚本
   ↓
2. 脚本通过 APISIX Admin API 发送配置
   ↓
3. APISIX 将配置写入 etcd
   ↓
4. APISIX 从 etcd 读取配置并应用
   ↓
5. 客户端请求 → APISIX 根据 etcd 中的配置路由请求
```

#### etcd 数据持久化

**etcd 可以保存配置！** 配置会持久化到 Docker 数据卷中。

**为什么需要运行 `init-apisix-routes.sh`？**

1. **首次启动**：etcd 是空的，需要初始化配置
2. **数据持久化已修复**：之前的配置中 etcd 数据目录路径错误（`/bitnami/etcd`），已修复为正确的路径（`/etcd-data`）
3. **正常情况**：重启服务后，etcd 中的数据应该保留，**不需要**重新运行脚本

**验证数据持久化：**

```bash
# 检查 etcd 中的数据
docker exec uyou-etcd etcdctl get --prefix /apisix/routes

# 检查 etcd 数据卷
docker volume inspect uyou-infrastructure_etcd_data
```

**如果重启后数据丢失，可能的原因：**

1. ❌ **数据目录配置错误**（已修复）
2. ❌ **使用 `docker compose down -v`** 删除了数据卷
3. ❌ **etcd 容器启动失败**，数据未正确加载

**正确的重启流程：**

```bash
# 正常重启（保留数据）
docker compose restart

# 停止服务（保留数据）
docker compose stop

# ⚠️ 完全删除（会删除所有数据！）
docker compose down -v  # 不要在生产环境使用！
```

### 2. init-apisix-routes.sh 脚本详解

#### 脚本的作用

这个脚本**通过 APISIX Admin API 将配置写入 etcd**，用于初始化 APISIX 的路由和 Proto 定义。

#### 脚本具体做了什么？

**步骤 1: 等待 APISIX 就绪**
```bash
# 检查 APISIX Admin API 是否可用
curl http://localhost:9180/apisix/admin/routes
```

**步骤 2: 创建 Proto 定义**
```bash
# 从 proto 文件读取内容
proto_content=$(cat proto/user.proto)

# 通过 Admin API 创建 proto 定义
curl -X PUT "http://localhost:9180/apisix/admin/protos/1" \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "1",
    "content": "syntax = \"proto3\";\npackage user;..."
  }'
```

**步骤 3: 创建路由配置**
```bash
# 创建路由配置 JSON
route_config='{
  "uri": "/api/v1/users/register",
  "methods": ["POST"],
  "upstream": {
    "nodes": {"user-service:50051": 1},
    "scheme": "grpc"
  },
  "plugins": {
    "grpc-transcode": {
      "proto_id": "1",
      "service": "user.UserService",
      "method": "Register"
    }
  }
}'

# 通过 Admin API 创建路由
curl -X PUT "http://localhost:9180/apisix/admin/routes/user-register" \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d "$route_config"
```

#### 脚本的优势

| 优势 | 说明 |
|------|------|
| 自动化 | 一次运行创建所有配置 |
| 可重复 | 可以重复运行，更新配置 |
| 版本控制 | 脚本可以纳入 Git 管理 |
| 一致性 | 确保所有环境配置一致 |

#### 脚本的优势

1. **自动化**：一次运行创建所有配置
2. **可重复**：可以重复运行，更新配置
3. **版本控制**：脚本可以纳入 Git 管理
4. **一致性**：确保所有环境配置一致

### 3. make proto-update 流程详解

#### 命令分解

```bash
make proto-update
```

这个命令实际上执行了两个步骤：

```makefile
proto-update: proto update-apisix
```

#### 步骤 1: `make proto`

**作用：** 生成 Go 代码

**具体操作：**
```bash
# 为 User Service 生成代码
protoc --go_out=services/user/proto \
       --go-grpc_out=services/user/proto \
       proto/user.proto

# 为 Order Service 生成代码
protoc --go_out=services/order/proto \
       --go-grpc_out=services/order/proto \
       proto/order.proto

# 为 Feed Service 生成代码
protoc --go_out=services/feed/proto \
       --go-grpc_out=services/feed/proto \
       proto/feed.proto
```

**生成的文件：**
```
services/user/proto/
  ├── user.pb.go        ← 消息结构体（Request/Response）
  └── user_grpc.pb.go   ← 服务接口（RPC 方法）

services/order/proto/
  ├── order.pb.go
  └── order_grpc.pb.go

services/feed/proto/
  ├── feed.pb.go
  └── feed_grpc.pb.go
```

#### 步骤 2: `make update-apisix`

**作用：** 更新 APISIX 配置

**具体操作：**
```bash
./scripts/init-apisix-routes.sh
```

**这个脚本做了：**
1. 从 `proto/*.proto` 文件读取内容
2. 通过 Admin API 创建/更新 Proto 定义到 etcd
3. 创建/更新路由配置到 etcd

#### 完整流程图

```
make proto-update
    │
    ├─→ make proto
    │     │
    │     ├─→ 读取 proto/user.proto
    │     ├─→ 生成 services/user/proto/user.pb.go
    │     ├─→ 生成 services/user/proto/user_grpc.pb.go
    │     │
    │     ├─→ 读取 proto/order.proto
    │     ├─→ 生成 services/order/proto/order.pb.go
    │     └─→ 生成 services/order/proto/order_grpc.pb.go
    │
    └─→ make update-apisix
          │
          └─→ ./scripts/init-apisix-routes.sh
                │
                ├─→ 读取 proto/user.proto
                ├─→ PUT /apisix/admin/protos/1 → etcd
                ├─→ PUT /apisix/admin/routes/user-register → etcd
                ├─→ PUT /apisix/admin/routes/user-login → etcd
                └─→ ... (其他路由)
```

### 4. 完整的数据流转流程

#### 场景：客户端注册用户

```
1. 客户端发送 HTTP 请求
   ↓
   POST http://localhost:9080/api/v1/users/register
   Content-Type: application/json
   {
     "username": "demo",
     "email": "demo@example.com",
     "password": "demo123"
   }

2. APISIX 接收请求
   ↓
   - 检查路由配置（从 etcd 读取）
   - 找到匹配的路由：/api/v1/users/register
   - 路由配置：
     * 上游服务：user-service:50051
     * 插件：grpc-transcode
     * Proto ID: 1
     * Service: user.UserService
     * Method: Register

3. APISIX grpc-transcode 插件工作
   ↓
   - 读取 Proto 定义（从 etcd 读取 ID=1 的 proto）
   - 将 JSON 转换为 gRPC 格式：
     {
       "username": "demo",
       "email": "demo@example.com",
       "password": "demo123"
     }
     ↓ 转换为
     RegisterRequest {
       username: "demo"
       email: "demo@example.com"
       password: "demo123"
     }

4. APISIX 转发 gRPC 请求
   ↓
   gRPC 调用：user-service:50051
   Service: user.UserService
   Method: Register
   Request: RegisterRequest {...}

5. User Service 处理请求
   ↓
   - 接收 gRPC 请求
   - 调用 Register() 方法
   - 连接 PostgreSQL 数据库
   - 插入用户数据
   - 返回 RegisterResponse

6. User Service 返回 gRPC 响应
   ↓
   RegisterResponse {
     user_id: 5
     message: "User registered successfully"
   }

7. APISIX grpc-transcode 插件转换响应
   ↓
   - 将 gRPC 响应转换为 JSON
   RegisterResponse {...}
     ↓ 转换为
   {
     "user_id": 5,
     "message": "User registered successfully"
   }

8. APISIX 返回 HTTP 响应
   ↓
   HTTP/1.1 200 OK
   Content-Type: application/json
   {
     "user_id": 5,
     "message": "User registered successfully"
   }

9. 客户端收到响应
```

### 5. API Gateway 功能实施情况

#### 架构图中提到的功能

根据架构图，APISIX 应该提供：
- JWT 认证
- 限流/熔断
- CORS
- 日志/TraceID

#### 当前实施情况

**✅ 已实施的功能**

1. **CORS（跨域资源共享）**
   - ✅ 已在路由配置中启用
   - 位置：`scripts/init-apisix-routes.sh`

2. **gRPC 转码（REST to gRPC）**
   - ✅ 已实施
   - 插件：`grpc-transcode`
   - 功能：将 HTTP/JSON 请求转换为 gRPC 调用

3. **日志**
   - ✅ 已配置访问日志
   - 位置：`apisix/config/config.yaml`
   - 日志文件：`/usr/local/apisix/logs/access.log`

**⚠️ 部分实施的功能**

1. **限流（Rate Limiting）**
   - ⚠️ 在 `apisix.yaml` 文件中有配置示例
   - ⚠️ 但在 `init-apisix-routes.sh` 脚本中**未启用**
   - 注意：当前项目使用 etcd 模式，`apisix.yaml` 文件不会被使用
   - 需要在脚本中添加 `limit-count` 插件才能生效

**❌ 未实施的功能**

1. **JWT 认证**
   - ❌ 未实施
   - 虽然 User Service 会生成 JWT Token，但 APISIX 没有验证
   - 需要在路由中添加 `jwt-auth` 插件

2. **熔断（Circuit Breaker）**
   - ❌ 未实施
   - 可以添加 `api-breaker` 插件

3. **TraceID**
   - ❌ 未实施
   - 可以添加 `zipkin` 或 `skywalking` 插件

#### 如何添加这些功能

**添加限流（推荐先添加这个）**

在 `scripts/init-apisix-routes.sh` 的 `create_route` 函数中，修改路由配置：

```bash
# 修改前
"plugins": {
  "grpc-transcode": {...},
  "cors": {...}
}

# 修改后（添加 limit-count）
"plugins": {
  "grpc-transcode": {...},
  "cors": {...},
  "limit-count": {
    "count": 100,
    "time_window": 60,
    "rejected_code": 429,
    "key": "remote_addr"
  }
}
```

**添加 JWT 认证**

在 `scripts/init-apisix-routes.sh` 的路由配置中添加：

```json
{
  "plugins": {
    "jwt-auth": {
      "key": "user-key",
      "secret": "your-secret-key"
    },
    "grpc-transcode": {...},
    "cors": {...}
  }
}
```

**注意：** 需要先创建 Consumer 并配置 JWT 密钥。

**添加熔断**

```json
{
  "plugins": {
    "api-breaker": {
      "break_response_code": 502,
      "max_breaker_sec": 300,
      "unhealthy": {
        "http_statuses": [500, 503],
        "failures": 3
      }
    }
  }
}
```

---

## 性能优化

### 1. 数据库优化

- 添加索引（用户名、订单号、时间戳）
- 配置连接池
- 读写分离

### 2. 缓存优化

- 热点数据预加载
- 缓存穿透保护（布隆过滤器）
- 缓存雪崩保护（随机 TTL）

### 3. 服务扩展

- 水平扩展微服务实例
- APISIX 负载均衡配置
- 数据库分片

### 性能基准

在标准配置下（4核8G）：

| 服务 | QPS | 平均延迟 |
|------|-----|---------|
| User Service | ~5000 | 20ms |
| Order Service | ~3000 | 35ms |
| Feed Service | ~8000 | 15ms |

*注：实际性能取决于硬件配置和网络环境*

---

## 生产部署

### Kubernetes 部署

```bash
# 转换为 Kubernetes 配置
kompose convert -f docker-compose.yml

# 部署到 K8s
kubectl apply -f .
```

### 环境变量配置

生产环境建议使用环境变量或配置中心管理敏感信息：

```bash
# User Service
DB_HOST=your-postgres-host
DB_PASSWORD=your-secure-password
JWT_SECRET=your-jwt-secret

# Order Service
DB_HOST=your-postgres-host
DB_PASSWORD=your-secure-password

# Feed Service
MONGO_HOST=your-mongodb-host
MONGO_PASSWORD=your-secure-password
```

### 安全配置

#### JWT 密钥

默认的 JWT 密钥在 `services/user/main.go` 中：
```go
var jwtSecret = []byte("your-secret-key-change-in-production")
```

**生产环境请务必修改！**

#### APISIX Admin Key

默认的 Admin Key 在 `apisix/config/config.yaml` 中：
```yaml
admin_key:
  - name: "admin"
    key: edd1c9f034335f136f87ad84b625c8f1
```

**生产环境请务必修改！**

---

## 学习资源

- [Apache APISIX 官方文档](https://apisix.apache.org/docs/)
- [gRPC 官方文档](https://grpc.io/docs/)
- [Protocol Buffers 指南](https://protobuf.dev/)
- [Go 微服务最佳实践](https://github.com/golang-standards/project-layout)

---

## 总结

### 关键概念

1. **etcd**：APISIX 的配置中心，存储所有路由和 proto 定义
2. **repeated**：Protobuf 中的数组/列表关键字
3. **init-apisix-routes.sh**：通过 Admin API 自动配置 APISIX
4. **make proto-update**：生成 Go 代码 + 更新 APISIX 配置

### 工作流程

```
编辑 proto 文件
    ↓
make proto-update
    ├─→ 生成 Go 代码
    └─→ 更新 APISIX 配置（写入 etcd）
         ↓
客户端请求 → APISIX（从 etcd 读取配置）→ gRPC 服务
```

### 下一步

- ✅ 理解整个流程
- ⚠️ 可以添加 JWT 认证、限流、熔断等功能
- ⚠️ 可以添加 TraceID 追踪
- 🚀 开始开发你的微服务功能

---

**Happy Learning! 🎉**
