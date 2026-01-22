# 社交系统微服务架构学习实例

这是一个基于 **Apache APISIX + Go 微服务** 的完整架构学习项目，帮助您从单体应用快速过渡到微服务架构。

## 🎯 项目目标

- 学习 API Gateway + 微服务架构模式
- 理解 REST to gRPC 转码机制
- 掌握多数据库（PostgreSQL + MongoDB）集成
- 实践 Docker 容器化部署
- 体验服务间 gRPC 通信

## 📐 架构图

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

## 🏗️ 项目结构

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
│       └── apisix.yaml    # 路由和插件配置
├── scripts/               # 工具脚本
│   ├── init-postgres.sh   # PostgreSQL 初始化
│   └── test-api.sh        # API 测试脚本
├── docker-compose.yml     # Docker 编排文件
├── Makefile               # 构建和管理命令
├── ARCHITECTURE.md        # 架构设计文档
└── README.md              # 本文件
```

## 🚀 快速开始

### 前置要求

- Docker 20.10+
- Docker Compose 2.0+
- Make (可选，用于快捷命令)

### 1. 启动所有服务

```bash
# 使用 Docker Compose 启动
docker compose up -d

# 或使用 Makefile
make run
```

### 2. 查看服务状态

```bash
docker compose ps
```

预期输出：
```
NAME                    STATUS
uyou-apisix             running
uyou-user-service       running
uyou-order-service      running
uyou-feed-service       running
uyou-postgres           healthy
uyou-mongodb            healthy
uyou-redis              healthy
uyou-etcd               healthy
```

### 3. 测试 API

```bash
# 运行测试脚本
./scripts/test-api.sh
```

或手动测试：

```bash
# 用户注册
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'

# 用户登录
curl -X POST http://localhost:9080/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "password123"
  }'
```

### 4. 访问管理界面

- **APISIX Dashboard**: http://localhost:9000
  - 用户名: `admin`
  - 密码: `admin`

- **APISIX Gateway**: http://localhost:9080

## 📚 核心概念

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

### 2. 微服务划分

#### User Service (端口 50051)
- **职责**: 用户认证、注册、个人资料管理
- **数据库**: PostgreSQL (强一致性)
- **缓存**: Redis (会话、用户信息)

#### Order Service (端口 50052)
- **职责**: 订单创建、查询、状态更新
- **数据库**: PostgreSQL (事务支持)
- **缓存**: Redis (订单缓存)

#### Feed Service (端口 50053)
- **职责**: 动态发布、时间线、点赞评论
- **数据库**: MongoDB (高吞吐、灵活 Schema)
- **缓存**: Redis (热点动态)

### 3. 数据库选型

| 服务 | 数据库 | 原因 |
|------|--------|------|
| User | PostgreSQL | 用户数据需要强一致性和事务支持 |
| Order | PostgreSQL | 订单涉及金额，需要 ACID 事务 |
| Feed | MongoDB | 动态内容灵活，读写量大，适合文档存储 |

### 4. 缓存策略

- **用户信息**: Cache-Aside 模式，TTL 24小时
- **订单信息**: Cache-Aside 模式，TTL 1小时
- **动态信息**: Cache-Aside 模式，TTL 1小时

## 🔧 开发指南

### Protobuf 基础知识

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

**实际示例：**

```protobuf
message CreateFeedRequest {
  int64 user_id = 1;      // 在二进制编码中用 "1" 标识
  string content = 2;     // 在二进制编码中用 "2" 标识
  repeated string images = 3;  // 在二进制编码中用 "3" 标识
  string location = 4;    // 在二进制编码中用 "4" 标识
}
```

在 Go 代码中使用时：
```go
req := &pb.CreateFeedRequest{
    UserId:   123,           // 对应编号 1
    Content:  "Hello",       // 对应编号 2
    Images:   []string{"..."}, // 对应编号 3
    Location: "Beijing",     // 对应编号 4
}
```

**总结：**
- `= 1, 2, 3, 4` 是字段的**唯一标识符**，用于二进制编码
- 不是字段的顺序，而是字段的**身份标识**
- 一旦定义，**不要随意更改**
- 不同 message 可以使用相同的编号

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

#### 添加新的 RPC 方法

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
6. 在 `apisix/config/apisix.yaml` 中添加路由

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

## 📊 监控和日志

### 查看日志

```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f user-service
docker compose logs -f apisix
```

### 查看 APISIX 访问日志

```bash
docker exec -it uyou-apisix tail -f /usr/local/apisix/logs/access.log
```

## 🛠️ 常用命令

```bash
# 启动所有服务
make run

# 停止所有服务
make stop

# 重启服务
make restart

# 查看日志
make logs

# 生成 Proto 文件
make proto

# 清理生成的文件
make clean
```

## 🔐 安全配置

### JWT 密钥

默认的 JWT 密钥在 `services/user/main.go` 中：
```go
var jwtSecret = []byte("your-secret-key-change-in-production")
```

**生产环境请务必修改！**

### APISIX Admin Key

默认的 Admin Key 在 `apisix/config/config.yaml` 中：
```yaml
admin_key:
  - name: "admin"
    key: edd1c9f034335f136f87ad84b625c8f1
```

**生产环境请务必修改！**

## 📈 性能优化建议

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

## 🚀 生产部署

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

## 🐛 故障排查

### 服务无法启动

1. 检查端口是否被占用：
   ```bash
   netstat -tlnp | grep -E '9080|50051|50052|50053'
   ```

2. 查看服务日志：
   ```bash
   docker compose logs user-service
   ```

### 数据库连接失败

1. 检查数据库健康状态：
   ```bash
   docker compose ps postgres
   ```

2. 手动连接测试：
   ```bash
   docker exec -it uyou-postgres psql -U postgres -d userdb
   ```

### APISIX 路由不生效

1. 检查 etcd 配置：
   ```bash
   docker exec -it uyou-etcd etcdctl get --prefix /apisix
   ```

2. 重启 APISIX：
   ```bash
   docker compose restart apisix
   ```

## 📖 学习资源

- [Apache APISIX 官方文档](https://apisix.apache.org/docs/)
- [gRPC 官方文档](https://grpc.io/docs/)
- [Protocol Buffers 指南](https://protobuf.dev/)
- [Go 微服务最佳实践](https://github.com/golang-standards/project-layout)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

---

**Happy Learning! 🎉**

如有问题，请查看 [ARCHITECTURE.md](./ARCHITECTURE.md) 了解更多架构细节。
