# uyou-Infrastructure 项目总结

## 项目概述

**uyou-Infrastructure** 是一个完整的 API Gateway + 微服务架构学习和生产框架，旨在帮助开发者从单体应用平滑过渡到微服务架构。

### 核心特性

1. **API Gateway 集中管理**：使用 Apache APISIX 作为统一入口
2. **REST to gRPC 自动转码**：客户端使用 REST，后端使用 gRPC
3. **生产级微服务脚手架**：一键生成符合最佳实践的微服务项目
4. **完整的文档体系**：从入门到精通的完整学习路径
5. **Docker 容器化**：一键启动完整的开发环境

### 技术栈

| 组件 | 技术 | 版本 |
|------|------|------|
| API Gateway | Apache APISIX | 3.8.0 |
| 配置中心 | etcd | 3.5.10 |
| 编程语言 | Go | 1.21+ |
| RPC 框架 | gRPC | 最新 |
| 数据库 | PostgreSQL / MongoDB | 15 / 7 |
| 缓存 | Redis | 7 |
| 容器 | Docker + Compose | 最新 |

## 项目结构

```
uyou-Infrastructure/
├── apisix/                      # APISIX 配置
│   └── config/
│       ├── config.yaml         # APISIX 主配置
│       └── routes/             # 路由配置片段
│           ├── user-routes.yaml
│           ├── order-routes.yaml
│           └── feed-routes.yaml
│
├── service-scaffold/           # 微服务脚手架
│   ├── template/               # 代码模板
│   │   ├── cmd/
│   │   ├── internal/
│   │   ├── pkg/
│   │   └── api/
│   ├── generator.go            # 生成器
│   ├── DESIGN.md               # 设计文档
│   └── README.md               # 使用指南
│
├── docs/                       # 文档
│   ├── README.md               # 文档导航
│   ├── CORE-CONCEPTS.md        # 核心概念详解
│   ├── ARCHITECTURE.md         # 架构设计详解
│   ├── MICROSERVICE-PATTERNS.md # 微服务设计模式
│   ├── DEVELOPMENT-GUIDE.md    # 开发指南
│   ├── API-REFERENCE.md        # API 文档
│   ├── OPERATIONS-GUIDE.md     # 运维指南
│   └── PROJECT-SUMMARY.md      # 本文件
│
├── scripts/                    # 工具脚本
│   ├── merge-apisix-configs.sh # 合并路由配置
│   ├── validate-config.sh      # 验证配置
│   └── test-api.sh             # API 测试
│
├── examples/                   # 示例代码
│   └── auth/                   # 认证示例
│
├── docker-compose.yml          # Docker 编排
├── Makefile                    # 快捷命令
└── README.md                   # 主文档
```

## 核心功能

### 1. API Gateway 管理

#### 动态路由配置
路由配置存储在 `apisix/config/routes/` 目录，支持多服务配置合并。

```yaml
# apisix/config/routes/user-routes.yaml
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
```

#### 部署配置
```bash
make update-apisix-merge
```

脚本会自动：
1. 合并所有路由配置
2. 上传 Proto 定义到 etcd
3. 通过 Admin API 部署路由
4. 验证配置正确性

### 2. 微服务脚手架

#### 一键生成服务
```bash
make new-service
```

#### 交互式配置
脚本会询问：
- 服务名称
- Git 仓库地址
- 数据库类型（PostgreSQL/MongoDB）
- 端口配置
- 是否使用消息队列

#### 生成的项目结构
```
user-service/
├── cmd/server/main.go           # 主程序
├── internal/
│   ├── handler/                 # gRPC Handler（控制层）
│   ├── service/                 # 业务逻辑层
│   ├── repository/              # 数据访问层
│   │   └── cache/               # 缓存层
│   ├── model/                   # 数据模型
│   ├── middleware/              # 中间件
│   │   ├── logging.go           # 日志中间件
│   │   ├── recovery.go          # 恢复中间件
│   │   ├── tracing.go           # 追踪中间件
│   │   └── validator.go         # 验证中间件
│   ├── validator/               # 数据验证
│   └── util/                    # 工具函数
├── pkg/
│   ├── config/                  # 配置管理（Viper）
│   ├── database/                # 数据库连接
│   │   ├── postgres.go
│   │   ├── mongodb.go
│   │   └── redis.go
│   ├── logger/                  # 日志（Zap）
│   └── errors/                  # 错误处理
├── api/proto/                   # Proto 定义
├── config/config.yaml           # 配置文件
├── migrations/                  # 数据库迁移
├── Makefile                     # 快捷命令
└── README.md                    # 项目文档
```

### 3. 分层架构

#### Handler 层（控制层）
```go
func (h *UserHandler) Register(ctx context.Context, req *pb.RegisterRequest) (*pb.RegisterResponse, error) {
    // 1. 参数验证
    if err := h.validator.ValidateRegister(req); err != nil {
        return nil, status.Error(codes.InvalidArgument, err.Error())
    }
    
    // 2. 调用 Service
    user, err := h.service.Register(ctx, req)
    if err != nil {
        return nil, err
    }
    
    // 3. 返回响应
    return &pb.RegisterResponse{UserId: user.ID}, nil
}
```

#### Service 层（业务逻辑层）
```go
func (s *UserService) Register(ctx context.Context, req *pb.RegisterRequest) (*model.User, error) {
    // 1. 检查用户是否存在
    exists, err := s.repo.ExistsByUsername(ctx, req.Username)
    
    // 2. 加密密码
    hashedPassword, err := util.HashPassword(req.Password)
    
    // 3. 创建用户
    user := &model.User{Username: req.Username, Password: hashedPassword}
    if err := s.repo.Create(ctx, user); err != nil {
        return nil, err
    }
    
    // 4. 缓存用户信息
    s.cacheRepo.Set(ctx, user)
    
    return user, nil
}
```

#### Repository 层（数据访问层）
```go
func (r *UserRepository) Create(ctx context.Context, user *model.User) error {
    query := `INSERT INTO users (username, email, password) VALUES ($1, $2, $3) RETURNING id`
    err := r.db.QueryRowContext(ctx, query, user.Username, user.Email, user.Password).Scan(&user.ID)
    return err
}
```

### 4. 中间件系统

#### 日志中间件
记录每个请求的方法、耗时、错误信息。

#### 恢复中间件
捕获 panic，记录堆栈，返回友好错误。

#### 追踪中间件
生成或传递 trace_id，支持分布式追踪。

#### 验证中间件
自动验证请求参数。

### 5. 配置管理

使用 Viper 支持多环境配置：

```yaml
server:
  port: 50051
  mode: development  # development, production

database:
  host: ${DB_HOST:localhost}
  port: ${DB_PORT:5432}
  user: ${DB_USER:postgres}
  password: ${DB_PASSWORD:postgres}
  database: ${DB_NAME:userdb}

redis:
  host: ${REDIS_HOST:localhost}
  port: ${REDIS_PORT:6379}

logger:
  level: debug  # debug, info, warn, error
  format: console  # json, console
```

### 6. 错误处理

统一的错误码和错误处理：

```go
var (
    ErrUserNotFound      = NewError(20001, "User not found")
    ErrUserAlreadyExists = NewError(20002, "User already exists")
    ErrInvalidPassword   = NewError(20003, "Invalid password")
)

// 自动转换为 gRPC 错误
return nil, errors.ToGRPCError(ErrUserNotFound)
```

## 工作流程

### 开发新功能

```
1. 定义 Proto API
   ↓
2. 生成代码 (make proto)
   ↓
3. 实现 Repository 层（数据访问）
   ↓
4. 实现 Service 层（业务逻辑）
   ↓
5. 实现 Handler 层（请求处理）
   ↓
6. 编写测试
   ↓
7. 本地运行测试
   ↓
8. 部署到 APISIX
```

### 部署新服务

```
1. 生成服务 (make new-service)
   ↓
2. 实现业务逻辑
   ↓
3. 构建 Docker 镜像
   ↓
4. 配置 APISIX 路由
   ↓
5. 部署路由 (make update-apisix-merge)
   ↓
6. 测试 API
```

## 最佳实践

### 1. 代码组织
- 严格遵循分层架构
- 使用依赖注入
- 接口隔离原则

### 2. 错误处理
- 使用统一错误码
- 记录详细日志
- 返回友好错误信息

### 3. 性能优化
- 使用缓存（Cache-Aside 模式）
- 数据库连接池
- 合理的索引设计

### 4. 安全性
- JWT 认证
- 参数验证
- SQL 注入防护
- 密码加密（bcrypt）

### 5. 可观测性
- 结构化日志
- 分布式追踪（trace_id）
- 性能监控
- 错误告警

## 扩展性设计

### 水平扩展
- 无状态服务设计
- 负载均衡（Round Robin / Consistent Hash）
- 数据库分片

### 垂直扩展
- 资源配置优化
- 连接池调优
- 缓存策略优化

### 服务拆分
- 按业务领域拆分
- 按数据特征拆分
- 按扩展需求拆分

## 学习路径

### 初级（1-2天）
1. 阅读主 README.md
2. 学习 CORE-CONCEPTS.md
3. 运行示例项目
4. 测试 API

### 中级（3-5天）
1. 深入学习 ARCHITECTURE.md
2. 使用脚手架生成服务
3. 实现自定义业务逻辑
4. 配置 APISIX 路由

### 高级（1-2周）
1. 学习性能优化
2. 实现复杂的微服务调用
3. 搭建监控系统
4. 生产环境部署

## 常用命令

### 微服务生成
```bash
make new-service         # 生成新的微服务
```

### APISIX 配置
```bash
make update-apisix-merge # 部署路由配置
make validate-config     # 验证配置
make cleanup-old-routes  # 清理旧路由
```

### 本地开发
```bash
make proto               # 生成 Proto 代码
make build               # 构建服务
make run                 # 启动服务
make test                # 运行测试
```

### Docker 管理
```bash
docker compose up -d     # 启动所有服务
docker compose down      # 停止所有服务
docker compose logs -f   # 查看日志
```

## 生产环境部署

### 1. 构建镜像
```bash
docker build -t user-service:v1.0 -f deployments/docker/Dockerfile .
```

### 2. 推送镜像
```bash
docker tag user-service:v1.0 registry.example.com/user-service:v1.0
docker push registry.example.com/user-service:v1.0
```

### 3. Kubernetes 部署
```bash
kubectl apply -f deployments/kubernetes/
```

### 4. 配置 APISIX
```bash
make update-apisix-merge
```

## 监控和运维

### 日志
- 使用结构化日志（JSON 格式）
- 集中日志收集（ELK Stack）
- 日志分级（Debug/Info/Warn/Error）

### 监控
- Prometheus 指标收集
- Grafana 可视化
- 告警规则配置

### 追踪
- Jaeger 分布式追踪
- trace_id 全链路追踪
- 性能瓶颈分析

## 常见问题

### Q: 如何添加新的微服务？
A: 使用 `make new-service` 生成新服务，然后配置 APISIX 路由。

### Q: 如何修改 APISIX 路由？
A: 编辑 `apisix/config/routes/*.yaml`，然后运行 `make update-apisix-merge`。

### Q: 如何调试微服务？
A: 使用 grpcurl 或 Postman 测试 gRPC 接口，查看日志排查问题。

### Q: 如何扩展服务？
A: 增加服务实例数量，APISIX 会自动负载均衡。

### Q: 如何处理数据库迁移？
A: 使用 golang-migrate 工具管理数据库版本。

## 参考资源

### 官方文档
- [Apache APISIX](https://apisix.apache.org/docs/)
- [gRPC](https://grpc.io/docs/)
- [Protocol Buffers](https://protobuf.dev/)
- [etcd](https://etcd.io/docs/)

### 最佳实践
- [Go 项目布局标准](https://github.com/golang-standards/project-layout)
- [Google SRE Book](https://sre.google/books/)
- [微服务设计模式](https://microservices.io/patterns/)

### 社区资源
- [Awesome Go](https://github.com/avelino/awesome-go)
- [Awesome gRPC](https://github.com/grpc-ecosystem/awesome-grpc)

## 贡献指南

欢迎贡献代码和文档！

### 提交 Issue
- 详细描述问题
- 提供复现步骤
- 附上日志和截图

### 提交 PR
- Fork 项目
- 创建特性分支
- 提交清晰的 commit 信息
- 通过所有测试
- 更新相关文档

## 许可证

本项目采用 MIT 许可证。

## 联系方式

- GitHub: https://github.com/yeegeek/uyou-Infrastructure
- Issues: https://github.com/yeegeek/uyou-Infrastructure/issues

---

**最后更新**: 2026-01-26
