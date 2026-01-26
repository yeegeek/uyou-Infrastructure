# 微服务脚手架使用指南

本脚手架用于快速生成符合 uyou 架构规范的微服务项目。

## 快速开始

### 1. 生成新服务

在项目根目录运行：

```bash
make new-service
```

### 2. 交互式配置

脚本会询问以下信息：

```
服务名称 (如 User, Order, Feed): User
Git 仓库地址 (如 github.com/uyou/uyou-user-service): github.com/yeegeek/uyou-user-service
Go 模块路径 [github.com/yeegeek/uyou-user-service]: 
gRPC 端口 [50051]: 50051
数据库类型 (postgres/mongodb) [postgres]: postgres
数据库名称 [userdb]: userdb
表名称 [users]: users
Redis DB (0-15) [0]: 0
缓存前缀 [user]: user
是否使用消息队列? (y/n) [n]: n
```

### 3. 确认配置

```
📋 配置确认
====================
服务名称: User
模块路径: github.com/yeegeek/uyou-user-service
Git 仓库: github.com/yeegeek/uyou-user-service
端口: 50051
数据库: PostgreSQL (userdb)
表名称: users
Redis DB: 0
缓存前缀: user
消息队列: false

确认生成? (y/n) [y]: y
```

### 4. 生成完成

脚手架会自动生成完整的项目结构：

```
user-service/
├── cmd/server/main.go           # 主程序
├── internal/
│   ├── handler/                 # gRPC Handler
│   ├── service/                 # 业务逻辑
│   ├── repository/              # 数据访问
│   ├── model/                   # 数据模型
│   ├── middleware/              # 中间件
│   ├── validator/               # 验证器
│   └── util/                    # 工具函数
├── pkg/
│   ├── config/                  # 配置管理
│   ├── database/                # 数据库连接
│   ├── logger/                  # 日志
│   └── errors/                  # 错误处理
├── api/proto/                   # Proto 定义
├── config/config.yaml           # 配置文件
├── Makefile                     # 快捷命令
└── README.md                    # 项目文档
```

## 后续开发步骤

### 1. 定义 API

编辑 `api/proto/user.proto`：

```protobuf
syntax = "proto3";

package user;

option go_package = "github.com/yeegeek/uyou-user-service/api/proto";

service UserService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
}

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

### 2. 生成 Proto 代码

```bash
cd user-service
make proto
```

这会生成：
- `api/proto/user.pb.go` - 消息类型
- `api/proto/user_grpc.pb.go` - gRPC 服务接口

### 3. 实现业务逻辑

#### 3.1 更新模型

编辑 `internal/model/model.go`：

```go
type User struct {
    ID        int64     `json:"id"`
    Username  string    `json:"username"`
    Email     string    `json:"email"`
    Password  string    `json:"password"`
    Avatar    string    `json:"avatar"`
    CreatedAt time.Time `json:"created_at"`
    UpdatedAt time.Time `json:"updated_at"`
}
```

#### 3.2 实现 Repository

编辑 `internal/repository/repository.go`，实现数据库操作。

#### 3.3 实现 Service

编辑 `internal/service/service.go`，实现业务逻辑。

#### 3.4 实现 Handler

编辑 `internal/handler/handler.go`，处理 gRPC 请求。

### 4. 配置数据库

编辑 `config/config.yaml`：

```yaml
server:
  port: 50051
  mode: development

database:
  host: localhost
  port: 5432
  user: postgres
  password: postgres
  database: userdb
  max_open_conns: 25
  max_idle_conns: 5
  conn_max_lifetime: 300

redis:
  host: localhost
  port: 6379
  password: ""
  db: 0

logger:
  level: debug
  format: console
  output: stdout
```

### 5. 数据库迁移

创建迁移文件 `migrations/000001_create_users_table.up.sql`：

```sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    avatar VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
```

运行迁移：

```bash
migrate -path migrations -database "postgresql://postgres:postgres@localhost:5432/userdb?sslmode=disable" up
```

### 6. 运行服务

```bash
make run
```

### 7. 测试服务

使用 grpcurl 测试：

```bash
grpcurl -plaintext -d '{"username":"alice","email":"alice@example.com","password":"pass123"}' \
  localhost:50051 user.UserService/Register
```

## 项目结构说明

### cmd/server/main.go
应用程序入口，负责：
- 加载配置
- 初始化日志
- 连接数据库
- 注册中间件
- 启动 gRPC 服务器

### internal/ 目录
私有代码，不可被外部导入。

#### handler/
gRPC Handler 层，负责：
- 接收 gRPC 请求
- 参数验证
- 调用 Service 层
- 返回响应

#### service/
业务逻辑层，负责：
- 实现业务逻辑
- 事务管理
- 调用 Repository 层
- 调用其他微服务

#### repository/
数据访问层，负责：
- 数据库操作
- 缓存操作
- 数据转换

#### model/
数据模型定义。

#### middleware/
中间件，包括：
- 日志中间件
- 恢复中间件
- 追踪中间件
- 验证中间件

#### validator/
数据验证器。

### pkg/ 目录
公共代码，可被外部导入。

#### config/
配置管理，使用 Viper 支持多环境。

#### database/
数据库连接管理。

#### logger/
结构化日志，使用 Zap。

#### errors/
统一错误处理和错误码。

## 最佳实践

### 1. 分层架构
严格遵循 Handler → Service → Repository 分层。

### 2. 依赖注入
通过构造函数注入依赖，便于测试。

```go
func NewUserService(repo *repository.UserRepository, logger *logger.Logger) *UserService {
    return &UserService{
        repo:   repo,
        logger: logger,
    }
}
```

### 3. 错误处理
使用统一的错误码和错误处理。

```go
if err != nil {
    return nil, errors.ErrUserNotFound
}
```

### 4. 日志记录
使用结构化日志，包含上下文信息。

```go
logger.Info("User registered", "user_id", user.ID, "username", user.Username)
```

### 5. 缓存策略
使用 Cache-Aside 模式：
- 读取：先查缓存，未命中再查数据库
- 更新：先更新数据库，再删除缓存

### 6. 测试
编写单元测试和集成测试。

```go
func TestUserService_Register(t *testing.T) {
    // 测试代码
}
```

## 常见问题

### Q: 如何添加新的 API？

1. 在 `api/proto/*.proto` 中定义新的 RPC 方法
2. 运行 `make proto` 生成代码
3. 在 Handler、Service、Repository 中实现逻辑

### Q: 如何修改数据库连接？

编辑 `config/config.yaml` 中的 `database` 配置。

### Q: 如何添加新的中间件？

1. 在 `internal/middleware/` 创建新文件
2. 实现 `grpc.UnaryServerInterceptor` 接口
3. 在 `cmd/server/main.go` 中注册

### Q: 如何部署服务？

1. 构建 Docker 镜像：`docker build -f deployments/docker/Dockerfile -t user-service .`
2. 推送到镜像仓库
3. 使用 Kubernetes 部署（参考 `deployments/kubernetes/`）

## 参考资源

- [Go 项目布局标准](https://github.com/golang-standards/project-layout)
- [gRPC Go 快速开始](https://grpc.io/docs/languages/go/quickstart/)
- [Protocol Buffers 指南](https://protobuf.dev/)
- [Zap 日志库](https://github.com/uber-go/zap)
- [Viper 配置管理](https://github.com/spf13/viper)

## 支持

如有问题，请提交 Issue 或联系团队。
