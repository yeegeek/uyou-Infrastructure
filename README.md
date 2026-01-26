# uyou-Infrastructure - API Gateway 微服务框架

**API Gateway 基础设施仓库** - Apache APISIX + Go 微服务架构学习框架

这是 **uyou 社交系统** 的完整 API Gateway 解决方案，帮助你从零开始理解和构建微服务架构。

## 🎯 学习目标

通过本项目，你将学会：
- ✅ API Gateway 网关架构设计
- ✅ REST to gRPC 协议转码机制
- ✅ 微服务多仓库架构最佳实践
- ✅ etcd 配置中心管理
- ✅ Docker 容器化开发
- ✅ gRPC 和 Protobuf 实战应用

---

## 📐 架构概览

```
┌─────────────┐
│   客户端     │ (REST/JSON)
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│    Apache APISIX Gateway (etcd)      │
│  • REST → gRPC 转码                  │
│  • 路由管理、限流、CORS              │
│  • 日志、监控、可观测性              │
└──────┬───────────────┬────────────────┘
       │               │               │
       ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│User Service │ │Order Service│ │Feed Service │
│ PostgreSQL  │ │ PostgreSQL  │ │  MongoDB    │
│ Redis       │ │ Redis       │ │  Redis      │
└─────────────┘ └─────────────┘ └─────────────┘
```

---

## 🚀 5 分钟快速开始

### 前置要求
- Docker 20.10+
- Docker Compose 2.0+

### 快速启动

```bash
# 1. 克隆项目
git clone https://github.com/uyou/uyou-Infrastructure.git
cd uyou-Infrastructure

# 2. 启动所有服务
docker compose up -d

# 3. 等待 1-2 分钟，部署路由配置
make update-apisix-merge

# 4. 测试 API
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "email": "demo@example.com",
    "password": "demo123"
  }'

# 预期响应：
# {"user_id":1,"message":"User registered successfully"}
```

---

## 📚 完整学习路径

### 第一层：理解架构（15 分钟）

#### 1.1 多仓库架构设计

本项目采用 **API Gateway 集中管理** 的架构：

```
uyou-api-gateway (本仓库)
├── APISIX 配置管理
├── 路由配置聚合
├── Docker 编排
└── apisix/config/routes/         # 集中管理路由
    ├── user-routes.yaml
    ├── order-routes.yaml
    └── feed-routes.yaml

微服务仓库 (独立)
├── uyou-user-service/   (用户服务)
├── uyou-order-service/  (订单服务)
└── uyou-feed-service/   (动态服务)
```

#### 1.2 技术栈

| 组件 | 技术 | 作用 |
|------|------|------|
| **API Gateway** | Apache APISIX 3.8.0 | 统一入口、协议转码 |
| **配置中心** | etcd 3.5.10 | 路由和 Proto 配置 |
| **服务开发** | Go + gRPC | 微服务实现 |
| **数据库** | PostgreSQL 15 + MongoDB 7 | 持久化存储 |
| **缓存** | Redis 7 | 性能优化 |
| **容器** | Docker + Compose | 开发和部署 |

#### 1.3 工作流程

```
编辑路由配置
  ↓
git commit
  ↓
make update-apisix-merge
  ↓
配置写入 etcd
  ↓
APISIX 读取应用
  ↓
配置生效
```

---

### 第二层：核心概念（30 分钟）

#### 2.1 etcd - 配置中心

**etcd** 是分布式键值存储，APISIX 用它存储所有配置：

```
etcd 存储内容：
├── /apisix/routes/          # 路由配置
├── /apisix/protos/          # Proto 定义
├── /apisix/upstreams/       # 上游服务地址
└── /apisix/services/        # 服务定义
```

**配置部署流程：**

```
scripts/merge-apisix-configs.sh
    ↓
APISIX Admin API (Port 9180)
    ↓ HTTP PUT /apisix/admin/routes/{id}
    ↓
etcd 存储
    ↓
APISIX 读取并应用
```

#### 2.2 Protobuf - 数据定义

**Proto 有两个用途：**

1. **编译时**：生成 Go 代码（微服务使用）
   ```bash
   make proto
   # 生成 services/user/proto/user.pb.go
   # 生成 services/user/proto/user_grpc.pb.go
   ```

2. **运行时**：注册到 APISIX（REST 转码使用）
   ```bash
   make update-apisix-merge
   # 通过 Admin API 上传 Proto 到 etcd
   ```

**数组定义 - `repeated` 关键字：**

```protobuf
message CreateFeedRequest {
  int64 user_id = 1;                    // 单个值
  repeated string images = 2;           // 数组 = Go: []string
  repeated int64 mentioned_user_ids = 3; // 数组 = Go: []int64
}
```

#### 2.3 REST to gRPC 转码

**APISIX 自动转码流程：**

```
客户端 REST 请求
    ↓
{"username": "demo", "email": "demo@example.com"}
    ↓
APISIX grpc-transcode 插件
    ↓
根据 Proto 定义转换为 gRPC
    ↓
RegisterRequest {username: "demo", email: "demo@example.com"}
    ↓
发送到 user-service:50051
    ↓
微服务返回 RegisterResponse
    ↓
APISIX 转换为 JSON
    ↓
{"user_id": 5, "message": "success"}
    ↓
返回客户端
```

#### 2.4 完整请求流程 - 9 步详解

```
1️⃣ 客户端发起 REST 请求
   POST /api/v1/users/register
   {"username": "alice", "password": "pass123"}

2️⃣ APISIX 接收请求
   ├─ 从 etcd 读取路由配置
   └─ 找到 /api/v1/users/register 的路由定义

3️⃣ APISIX 路由匹配
   ├─ URI 匹配成功
   ├─ 方法匹配成功 (POST)
   └─ 执行 grpc-transcode 插件

4️⃣ 获取 Proto 定义
   └─ 从 etcd 读取 proto_id: "1" 的 Proto

5️⃣ JSON to gRPC 转码
   ├─ 解析 JSON 数据
   ├─ 根据 Proto 定义构建 Protobuf 消息
   └─ 创建 RegisterRequest 对象

6️⃣ 转发 gRPC 请求
   └─ gRPC 调用 user.UserService/Register
      目标：user-service:50051

7️⃣ 微服务处理
   ├─ 接收 gRPC 请求
   ├─ 验证数据、加密密码
   ├─ 写入 PostgreSQL
   └─ 返回 RegisterResponse

8️⃣ gRPC to JSON 转码
   ├─ 读取 Proto 定义
   └─ RegisterResponse → JSON 格式

9️⃣ 返回客户端
   HTTP 200 OK
   {"user_id": 5, "message": "success"}
```

---

### 第三层：实践操作（45 分钟）

#### 3.1 查看服务状态

```bash
# 查看所有服务
docker compose ps

# 查看 APISIX 日志
docker compose logs -f apisix

# 测试 Admin API
curl http://localhost:9180/apisix/admin/routes \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"
```

#### 3.2 编辑路由配置

```bash
# 编辑用户服务路由
vim apisix/config/routes/user-routes.yaml

# 路由配置格式
routes:
  - name: user-register
    uri: /api/v1/users/register
    methods: [POST]
    upstream:
      type: roundrobin
      nodes:
        "user-service:50051": 1
      scheme: grpc
    plugins:
      grpc-transcode:
        proto_id: "1"
        service: user.UserService
        method: Register
      cors:
        allow_origins: "*"
        allow_methods: "GET,POST,PUT,DELETE,OPTIONS"
```

#### 3.3 部署配置

```bash
# 验证配置语法
make validate-config

# 部署配置到 APISIX
make update-apisix-merge

# 查看已部署的路由
curl http://localhost:9180/apisix/admin/routes \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" | jq
```

#### 3.4 测试 API

**用户服务：**

```bash
# 注册用户
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "alice",
    "email": "alice@example.com",
    "password": "pass123"
  }'

# 登录
curl -X POST http://localhost:9080/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "alice",
    "password": "pass123"
  }'

# 获取用户信息
curl http://localhost:9080/api/v1/users/1
```

**订单服务：**

```bash
# 创建订单
curl -X POST http://localhost:9080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 1,
    "items": [
      {
        "product_id": 1001,
        "product_name": "商品A",
        "quantity": 2,
        "price": 99.99
      }
    ],
    "total_amount": 199.98
  }'
```

**动态服务：**

```bash
# 发布动态
curl -X POST http://localhost:9080/api/v1/feeds \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 1,
    "content": "今天天气真好！",
    "images": [
      "https://example.com/photo.jpg"
    ],
    "location": "北京"
  }'

# 获取时间线
curl http://localhost:9080/api/v1/feeds/timeline?page=1&limit=20
```

#### 3.5 本地开发

```bash
# 克隆微服务到 services/ 目录
mkdir -p services
cd services
git clone https://github.com/uyou/uyou-user-service.git user
git clone https://github.com/uyou/uyou-order-service.git order
git clone https://github.com/uyou/uyou-feed-service.git feed
cd ..

# 生成 Proto 代码
make proto

# 编辑微服务代码
vim services/user/main.go

# 更新路由配置
vim apisix/config/routes/user-routes.yaml

# 部署配置
make update-apisix-merge
```

---

### 第四层：故障排查（20 分钟）

#### 4.1 常见问题

**问题：API 返回 404**
```bash
# 1. 检查路由是否部署
curl http://localhost:9180/apisix/admin/routes \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"

# 2. 验证配置
make validate-config

# 3. 重新部署
make update-apisix-merge
```

**问题：服务无法连接**
```bash
# 1. 查看服务状态
docker compose ps

# 2. 查看服务日志
docker compose logs user-service

# 3. 重启服务
docker compose restart user-service
```

**问题：数据库连接失败**
```bash
# 1. 检查数据库状态
docker compose ps postgres

# 2. 初始化数据库
./scripts/init-postgres.sh

# 3. 重启数据库
docker compose restart postgres
```

**问题：etcd 数据损坏**
```bash
# 1. 停止服务
docker compose down

# 2. 删除 etcd 卷
docker volume rm uyou-Infrastructure_etcd_data

# 3. 重启
docker compose up -d

# 4. 重新部署配置
make update-apisix-merge
```

---

## 📁 项目结构

```
uyou-Infrastructure/
├── apisix/                          # APISIX 配置
│   ├── config/
│   │   ├── config.yaml             # APISIX 主配置（etcd 模式）
│   │   └── routes/                 # 微服务路由片段
│   │       ├── user-routes.yaml    # 用户服务路由
│   │       ├── order-routes.yaml   # 订单服务路由
│   │       └── feed-routes.yaml    # 动态服务路由
│   └── config/routes/README.md     # 路由说明
│
├── scripts/                         # 工具脚本
│   ├── merge-apisix-configs.sh     # 合并和部署路由配置
│   ├── validate-config.sh          # 验证配置
│   ├── init-postgres.sh            # PostgreSQL 初始化
│   └── test-api.sh                 # API 测试
│
├── services/                        # 本地开发目录 (.gitignore)
│   ├── user/                       # 克隆微服务进行本地开发
│   ├── order/
│   └── feed/
│
├── docs/                            # 其他文档
│   └── PROTO-EXPLANATION.md        # Proto 详解
│
├── docker-compose.yml              # 所有服务编排
├── Makefile                        # 快捷命令
├── .cursorrules                    # Cursor IDE 规则
└── README.md                       # 本文件
```

---

## 🔧 常用命令

### 服务管理

```bash
make run              # 启动所有服务
make stop             # 停止所有服务
make restart          # 重启服务
make logs             # 查看日志
```

### 配置管理

```bash
make update-apisix-merge    # 合并并部署路由配置（推荐）
make validate-config        # 验证配置
```

### 本地开发

```bash
make proto             # 生成 Proto 代码
make build             # 构建微服务
make clean             # 清理生成的文件
```

### 查看帮助

```bash
make help
```

---

## 🌐 访问地址

| 服务 | 地址 | 用途 |
|------|------|------|
| APISIX 网关 | http://localhost:9080 | 客户端 API 入口 |
| APISIX Admin | http://localhost:9180 | 管理界面和 API |
| PostgreSQL | localhost:5432 | 用户/订单数据库 |
| MongoDB | localhost:27017 | 动态数据库 |
| Redis | localhost:6379 | 缓存 |
| etcd | localhost:2379 | 配置中心 |

---

## 💡 关键概念总结

### 1. 多仓库架构
- 网关仓库：集中管理配置
- 微服务仓库：独立开发、独立部署
- Git 管理：所有配置都在 Git 中，可追溯

### 2. REST to gRPC 转码
```
REST 请求 → APISIX 转码 → gRPC 调用 → 微服务处理
```
- APISIX 使用 `grpc-transcode` 插件
- 需要 Proto 定义来理解数据结构
- 完全对客户端透明

### 3. etcd 配置中心
- 存储所有 APISIX 配置
- 支持动态更新（无需重启）
- 高可用和分布式

### 4. Protobuf 和 gRPC
- Proto 定义数据结构和服务
- gRPC 用于微服务间通信
- `repeated` 关键字表示数组

### 5. Docker 容器化
- 统一的开发环境
- 本地与生产环境一致
- 方便快速部署

### 6. 安全认证架构
- **JWT 认证**：APISIX 网关层保护公共接口
- **接口分离**：公共接口和内部接口分离设计

---

## 🔐 安全认证架构

本框架实现了安全认证机制：

### 1. APISIX 网关层 JWT 认证

**用途**：保护通过 APISIX 暴露的公共接口

**工作原理**：
1. 用户登录后获取 JWT Token
2. 后续请求在 Header 中携带 Token：`Authorization: Bearer <token>`
3. APISIX 验证 Token 有效性
4. 验证通过后转发请求到后端服务

**配置方式**：
- JWT Consumer 在部署时自动创建（`make update-apisix-merge`）
- JWT Secret 通过环境变量 `APISIX_JWT_SECRET` 配置
- 路由配置中通过 `jwt-auth: {}` 插件启用认证

**重要提示**：
- 如果之前部署过没有 JWT 认证的路由，需要先清理旧路由
- 运行 `./scripts/cleanup-old-routes.sh` 清理旧路由配置
- 或者手动删除：`curl -X DELETE http://localhost:9180/apisix/admin/routes/<route-name> -H "X-API-KEY: <admin-key>"`

**公开接口**（不需要 JWT）：
- `/api/v1/users/register` - 用户注册
- `/api/v1/users/login` - 用户登录

**受保护接口**（需要 JWT）：
- `/api/v1/users/*` - 获取/更新用户信息
- `/api/v1/orders/*` - 订单相关操作
- `/api/v1/feeds/*` - 动态相关操作

**使用示例**：
```bash
# 1. 登录获取 Token
TOKEN=$(curl -X POST http://localhost:9080/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"123"}' | jq -r '.token')

# 2. 使用 Token 访问受保护接口
curl -X GET http://localhost:9080/api/v1/users/1 \
  -H "Authorization: Bearer $TOKEN"
```

**重要说明**：
- `consumer_key` 是 APISIX 内部标识符，用于匹配 JWT token 中的 `key` 字段
- 微服务生成 JWT token 时，payload **必须包含** `"key": "user_key"` 字段
- 微服务从 gRPC metadata 中获取用户信息（参见 [JWT 认证流程文档](docs/JWT-AUTH-FLOW.md)）

**为什么需要 `key` 字段？**
- APISIX 使用 token payload 中的 `key` 字段来查找对应的 Consumer
- 然后使用该 Consumer 的 `secret` 来验证 token 签名
- 如果不包含 `key` 字段，APISIX 无法知道用哪个 Consumer 来验证，认证会失败

详细文档：
- [consumer_key 作用详解](docs/CONSUMER-KEY-EXPLANATION.md) - **强烈推荐阅读**，解释 `user_key` 的作用
- [JWT 认证流程](docs/JWT-AUTH-FLOW.md) - 完整的 JWT 认证流程和代码示例

### 2. 公共接口 vs 内部接口分离

**设计原则**：
- **公共接口**：通过 APISIX 暴露，使用 JWT 认证，供客户端调用
- **内部接口**：不通过 APISIX，直接 gRPC 调用，供服务间调用（内网安全，无需额外认证）

**实现方式**：
- 使用不同的 proto 文件：`user.proto`（公共）和 `user-internal.proto`（内部）
- 公共接口在路由配置中注册，内部接口不在 APISIX 路由中
- 内部接口只能通过直接 gRPC 连接访问

**示例**：
```protobuf
// user.proto - 公共接口
service UserService {
  rpc Register(...) returns (...);  // 通过 APISIX 访问
  rpc Login(...) returns (...);      // 通过 APISIX 访问
  rpc GetUser(...) returns (...);    // 通过 APISIX 访问（需要 JWT）
}

// user-internal.proto - 内部接口
service UserInternalService {
  rpc BatchGetUsers(...) returns (...);  // 直接 gRPC 调用（内网安全）
  rpc ValidateUserPermission(...) returns (...);  // 直接 gRPC 调用
}
```

详细文档：参见 [docs/INTERFACE-SEPARATION.md](docs/INTERFACE-SEPARATION.md)

### 测试认证功能

运行测试脚本：
```bash
./examples/auth/test_auth.sh
```

该脚本会测试：
- JWT 认证（注册、登录、访问受保护接口）

---

## 🎓 深入学习

### Proto 文件详解

Proto 文件的两个用途：

1. **编译时**：`make proto` 生成 Go 代码
   - 微服务代码使用
   - 生成 `.pb.go` 和 `_grpc.pb.go` 文件

2. **运行时**：`make update-apisix-merge` 注册到 APISIX
   - APISIX REST 转码使用
   - 通过 Admin API 上传到 etcd

完整的工作流程：
```
修改 Proto → make proto → 生成 Go 代码
                       ↓
编辑路由配置 → make update-apisix-merge → 上传 Proto 到 APISIX
                                    ↓
                              客户端 → APISIX → 微服务
```

### 配置文件详解

**apisix/config/routes/user-routes.yaml 关键字段：**

```yaml
routes:
  - name: user-register              # 路由名称（唯一标识）
    uri: /api/v1/users/register      # HTTP 路径
    methods: [POST]                  # HTTP 方法
    upstream:
      type: roundrobin               # 负载均衡类型
      nodes:
        "user-service:50051": 1       # 后端服务地址和权重
      scheme: grpc                    # 与后端通信协议（gRPC）
    plugins:
      grpc-transcode:                 # gRPC 转码插件
        proto_id: "1"                 # Proto 定义 ID
        service: user.UserService     # Proto service 名
        method: Register              # Proto method 名
      cors:                           # CORS 跨域支持
        allow_origins: "*"
        allow_methods: "GET,POST,PUT,DELETE,OPTIONS"
        allow_headers: "*"
```

---

## 📝 常见问题

### Q1: 为什么需要 etcd？

A: etcd 作为 APISIX 的配置中心，支持：
- 配置热更新（无需重启 APISIX）
- 分布式部署
- 高可用性
- 版本管理

### Q2: Proto 文件应该放在哪里？

A: 
- 当前项目：在微服务仓库中（每个服务一个）
- 开发时：克隆到 services/ 本地开发
- 部署时：通过脚本同步到网关

### Q3: 如何添加新的 API 路由？

A:
1. 编辑 `apisix/config/routes/{service}-routes.yaml`
2. 添加新路由定义
3. 运行 `make update-apisix-merge`
4. 测试 API

### Q4: 如何修改 Proto 定义？

A:
1. 编辑 `proto/{service}.proto`
2. 运行 `make proto` 生成 Go 代码
3. 更新路由配置（如果需要）
4. 运行 `make update-apisix-merge` 部署

### Q5: 服务之间如何通信？

A: 
- **通过 APISIX**：客户端 → APISIX → 微服务（REST to gRPC）
- **直接 gRPC**：微服务 ↔ 微服务（服务间调用）

---

## 📊 技术指标

| 指标 | 值 |
|------|-----|
| APISIX 版本 | 3.8.0 |
| etcd 版本 | 3.5.10 |
| Go 版本 | 1.21+ |
| PostgreSQL | 15 |
| MongoDB | 7 |
| Redis | 7 |

---

## 🚀 下一步

1. **快速开始**（5 分钟）
   - 按照 [5 分钟快速开始](#5-分钟快速开始) 启动项目

2. **理解架构**（15 分钟）
   - 学习 [多仓库架构设计](#11-多仓库架构设计)
   - 查看 [技术栈](#12-技术栈)

3. **深入学习**（30 分钟）
   - 理解 [etcd 配置中心](#21-etcd---配置中心)
   - 掌握 [REST to gRPC 转码](#23-rest-to-grpc-转码)

4. **实践操作**（45 分钟）
   - [编辑和部署路由](#32-编辑路由配置)
   - [测试各个服务](#34-测试-api)
   - [本地开发](#35-本地开发)

5. **问题排查**（20 分钟）
   - 参考 [故障排查](#第四层故障排查20-分钟)
   - 查看 [常见问题](#📝-常见问题)

---

## 📖 相关资源

- [APISIX 官网](https://apisix.apache.org/)
- [gRPC 官网](https://grpc.io/)
- [Protocol Buffers 文档](https://developers.google.com/protocol-buffers)
- [Docker 文档](https://docs.docker.com/)

---

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

---

## 📄 许可证

MIT License

---

**祝你学习愉快！🎉**

有任何问题，请查看本文档的相应章节或提交 Issue。
