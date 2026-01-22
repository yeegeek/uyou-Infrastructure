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
docker-compose up -d

# 或使用 Makefile
make run
```

### 2. 查看服务状态

```bash
docker-compose ps
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

### 修改 Proto 定义

1. 编辑 `proto/*.proto` 文件
2. 重新生成代码：
   ```bash
   make proto
   ```
3. 更新 `apisix/config/apisix.yaml` 中的 proto 定义
4. 重启服务：
   ```bash
   make restart
   ```

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
docker-compose up -d postgres mongodb redis etcd

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
docker-compose logs -f

# 查看特定服务日志
docker-compose logs -f user-service
docker-compose logs -f apisix
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
   docker-compose logs user-service
   ```

### 数据库连接失败

1. 检查数据库健康状态：
   ```bash
   docker-compose ps postgres
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
   docker-compose restart apisix
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
