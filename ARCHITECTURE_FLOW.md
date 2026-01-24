# 架构流程详解

本文档详细解释整个微服务架构的工作流程和各个组件的作用。

## 📋 目录

1. [etcd 的作用和必要性](#1-etcd-的作用和必要性)
2. [Protobuf 中的数组（repeated）](#2-protobuf-中的数组repeated)
3. [init-apisix-routes.sh 脚本详解](#3-init-apisix-routessh-脚本详解)
4. [make proto-update 流程详解](#4-make-proto-update-流程详解)
5. [完整的数据流转流程](#5-完整的数据流转流程)
6. [API Gateway 功能实施情况](#6-api-gateway-功能实施情况)

---

## 1. etcd 的作用和必要性

### etcd 是什么？

**etcd** 是一个分布式键值存储系统，在 APISIX 架构中充当**配置中心**的角色。

### etcd 在 APISIX 中的作用

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

### 是否必须？

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

**关于 `apisix.yaml` 文件：**
- 项目中的 `apisix/config/apisix.yaml` 文件是**文件驱动模式**的配置文件
- 在当前项目（传统模式 + etcd）中，这个文件**不会被 APISIX 读取**
- 实际配置通过 `scripts/init-apisix-routes.sh` 脚本写入 etcd
- 如果切换到文件驱动模式，需要修改 `config.yaml` 中的 `config_provider` 为 `yaml`

### etcd 的工作流程

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

---

## 2. Protobuf 中的数组（repeated）

### repeated 就是数组

在 Protobuf 中，**`repeated` 关键字表示数组/列表**。

### 示例说明

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

### 在代码中的使用

**Protobuf 定义：**
```protobuf
message CreateFeedRequest {
  repeated string images = 3;  // 字符串数组
}
```

**Go 代码中使用：**
```go
req := &pb.CreateFeedRequest{
    Images: []string{
        "https://example.com/image1.jpg",
        "https://example.com/image2.jpg",
        "https://example.com/image3.jpg",
    },
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

### 其他 repeated 示例

```protobuf
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

**对应 Go 代码：**
```go
req := &pb.CreateOrderRequest{
    UserId: 123,
    Items: []*pb.OrderItem{  // OrderItem 指针数组
        {ProductId: 1001, ProductName: "商品A", Quantity: 2, Price: 99.99},
        {ProductId: 1002, ProductName: "商品B", Quantity: 1, Price: 49.99},
    },
    TotalAmount: 249.97,
}
```

**总结：**
- ✅ `repeated` = 数组/列表
- ✅ `repeated string` = 字符串数组 `[]string`
- ✅ `repeated OrderItem` = OrderItem 数组 `[]*pb.OrderItem`

---

## 3. init-apisix-routes.sh 脚本详解

### 脚本的作用

这个脚本**通过 APISIX Admin API 将配置写入 etcd**，相当于在 APISIX Dashboard 中手动配置路由。

### 脚本具体做了什么？

让我们逐步分析：

#### 步骤 1: 等待 APISIX 就绪

```bash
# 检查 APISIX Admin API 是否可用
curl http://localhost:9180/apisix/admin/routes
```

#### 步骤 2: 创建 Proto 定义

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

**这一步相当于：**
- 在 APISIX Dashboard 中点击 "Proto" → "创建"
- 输入 proto ID: `1`
- 粘贴 proto 文件内容

#### 步骤 3: 创建路由配置

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

**这一步相当于：**
- 在 APISIX Dashboard 中点击 "路由" → "创建路由"
- 配置路径：`/api/v1/users/register`
- 配置方法：`POST`
- 配置上游服务：`user-service:50051`
- 配置 gRPC 转码插件

### 脚本 vs Dashboard 对比

| 操作 | Dashboard 操作 | 脚本操作 |
|------|---------------|----------|
| 创建 Proto | 点击界面，手动输入 | `create_proto()` 函数自动读取文件 |
| 创建路由 | 点击界面，填写表单 | `create_route()` 函数自动生成 JSON |
| 批量操作 | 需要逐个点击 | 脚本循环创建所有路由 |

### 脚本的优势

1. **自动化**：一次运行创建所有配置
2. **可重复**：可以重复运行，更新配置
3. **版本控制**：脚本可以纳入 Git 管理
4. **一致性**：确保所有环境配置一致

### 手动操作对比

如果你想手动操作，需要：

1. 访问 http://localhost:9000
2. 登录 Dashboard（admin/admin）
3. 点击 "Proto" → "创建"
   - 输入 ID: `1`
   - 粘贴 `proto/user.proto` 的内容
4. 点击 "路由" → "创建路由"
   - 配置路径、方法、上游等
5. 重复步骤 3-4 创建所有路由（7个路由 × 3个服务 = 21次操作）

**脚本只需要运行一次：**
```bash
./scripts/init-apisix-routes.sh
```

---

## 4. make proto-update 流程详解

### 命令分解

```bash
make proto-update
```

这个命令实际上执行了两个步骤：

```makefile
proto-update: proto update-apisix
```

### 步骤 1: `make proto`

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

**这些文件包含：**
- `CreateFeedRequest` 结构体
- `CreateFeedResponse` 结构体
- `FeedServiceClient` 接口
- `FeedServiceServer` 接口

### 步骤 2: `make update-apisix`

**作用：** 更新 APISIX 配置

**具体操作：**
```bash
./scripts/init-apisix-routes.sh
```

**这个脚本做了：**
1. 从 `proto/*.proto` 文件读取内容
2. 通过 Admin API 创建/更新 Proto 定义到 etcd
3. 创建/更新路由配置到 etcd

### 完整流程图

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

### 数据存储位置

```
┌─────────────────────────────────────────┐
│              etcd (配置中心)              │
├─────────────────────────────────────────┤
│ /apisix/protos/1                        │ ← Proto 定义
│ /apisix/routes/user-register            │ ← 路由配置
│ /apisix/routes/user-login               │ ← 路由配置
│ /apisix/routes/order-create             │ ← 路由配置
│ ...                                     │
└─────────────────────────────────────────┘
         ↑
         │ APISIX 读取配置
         │
┌─────────────────────────────────────────┐
│            APISIX (API 网关)            │
└─────────────────────────────────────────┘
```

---

## 5. 完整的数据流转流程

### 场景：客户端注册用户

让我们追踪一个完整的请求流程：

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

### 关键组件交互图

```
┌──────────┐
│  客户端   │
└────┬─────┘
     │ HTTP POST /api/v1/users/register
     │ JSON: {"username": "demo", ...}
     ▼
┌─────────────────────────────────────┐
│         APISIX (API 网关)            │
│  ┌───────────────────────────────┐  │
│  │  1. 路由匹配                  │  │ ← 从 etcd 读取路由配置
│  │     /api/v1/users/register    │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  2. grpc-transcode 插件        │  │ ← 从 etcd 读取 proto 定义
│  │     JSON → gRPC                │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  3. 转发到上游服务             │  │
│  └───────────────────────────────┘  │
└────┬────────────────────────────────┘
     │ gRPC: user.UserService/Register
     ▼
┌─────────────────────────────────────┐
│      User Service (gRPC 服务)        │
│  ┌───────────────────────────────┐  │
│  │  Register() 方法              │  │
│  │  - 验证数据                   │  │
│  │  - 加密密码                   │  │
│  └──────┬────────────────────────┘  │
│         │ SQL INSERT                │
│         ▼                           │
│  ┌───────────────────────────────┐  │
│  │   PostgreSQL 数据库          │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

---

## 6. API Gateway 功能实施情况

### 架构图中提到的功能

根据 README.md 中的架构图，APISIX 应该提供：
- JWT 认证
- 限流/熔断
- CORS
- 日志/TraceID

### 当前实施情况

#### ✅ 已实施的功能

1. **CORS（跨域资源共享）**
   - ✅ 已在路由配置中启用
   - 位置：`scripts/init-apisix-routes.sh`
   ```json
   "cors": {
     "allow_origins": "*",
     "allow_methods": "GET,POST,PUT,DELETE,OPTIONS",
     "allow_headers": "*"
   }
   ```

2. **gRPC 转码（REST to gRPC）**
   - ✅ 已实施
   - 插件：`grpc-transcode`
   - 功能：将 HTTP/JSON 请求转换为 gRPC 调用

3. **日志**
   - ✅ 已配置访问日志
   - 位置：`apisix/config/config.yaml`
   - 日志文件：`/usr/local/apisix/logs/access.log`

#### ⚠️ 部分实施的功能

1. **限流（Rate Limiting）**
   - ⚠️ 在 `apisix.yaml` 文件中有配置示例
   - ⚠️ 但在 `init-apisix-routes.sh` 脚本中**未启用**
   - 注意：当前项目使用 etcd 模式，`apisix.yaml` 文件不会被使用
   - 需要在脚本中添加 `limit-count` 插件才能生效

#### ❌ 未实施的功能

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

### 如何添加这些功能

#### 添加限流（推荐先添加这个）

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

**具体操作：**
1. 编辑 `scripts/init-apisix-routes.sh`
2. 在第 47-60 行的 `plugins` 部分添加 `limit-count` 配置
3. 运行 `make update-apisix` 更新配置

#### 添加 JWT 认证

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

#### 添加熔断

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

## 📝 总结

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
