# 生产级微服务脚手架设计

本文档说明 uyou 微服务脚手架的设计思路和目录结构，参考大厂最佳实践。

## 设计目标

1. **标准化**：统一的项目结构，降低学习成本
2. **可维护**：清晰的分层架构，易于理解和修改
3. **可扩展**：模块化设计，方便添加新功能
4. **生产就绪**：包含配置管理、日志、监控等生产环境必需功能

## 参考标准

- [golang-standards/project-layout](https://github.com/golang-standards/project-layout)
- Google SRE 最佳实践
- 字节跳动、阿里巴巴微服务规范

## 目录结构

```
service-name/
├── cmd/                        # 应用程序入口
│   └── server/
│       └── main.go            # 主程序
│
├── internal/                   # 私有代码（不可被外部导入）
│   ├── handler/               # gRPC Handler（控制层）
│   │   ├── user_handler.go
│   │   └── user_handler_test.go
│   │
│   ├── service/               # 业务逻辑层
│   │   ├── user_service.go
│   │   └── user_service_test.go
│   │
│   ├── repository/            # 数据访问层
│   │   ├── user_repository.go
│   │   ├── user_repository_test.go
│   │   └── cache/
│   │       └── user_cache.go
│   │
│   ├── model/                 # 数据模型
│   │   ├── user.go
│   │   └── dto/              # 数据传输对象
│   │       └── user_dto.go
│   │
│   ├── middleware/            # 中间件
│   │   ├── auth.go           # 认证中间件
│   │   ├── logging.go        # 日志中间件
│   │   ├── recovery.go       # 恢复中间件
│   │   ├── tracing.go        # 追踪中间件
│   │   └── validator.go      # 验证中间件
│   │
│   ├── validator/             # 数据验证
│   │   ├── user_validator.go
│   │   └── common_validator.go
│   │
│   ├── util/                  # 工具函数
│   │   ├── crypto.go         # 加密工具
│   │   ├── time.go           # 时间工具
│   │   └── string.go         # 字符串工具
│   │
│   └── worker/                # 后台任务
│       ├── email_worker.go
│       └── cleanup_worker.go
│
├── pkg/                        # 公共代码（可被外部导入）
│   ├── config/                # 配置管理
│   │   ├── config.go
│   │   └── config.yaml
│   │
│   ├── database/              # 数据库连接
│   │   ├── postgres.go
│   │   ├── mongodb.go
│   │   └── redis.go
│   │
│   ├── logger/                # 日志
│   │   └── logger.go
│   │
│   ├── errors/                # 错误处理
│   │   ├── errors.go
│   │   └── codes.go
│   │
│   └── queue/                 # 消息队列
│       ├── rabbitmq.go
│       └── kafka.go
│
├── api/                        # API 定义
│   └── proto/
│       ├── user.proto
│       ├── user.pb.go
│       └── user_grpc.pb.go
│
├── migrations/                 # 数据库迁移
│   ├── 000001_create_users_table.up.sql
│   ├── 000001_create_users_table.down.sql
│   └── README.md
│
├── scripts/                    # 脚本
│   ├── build.sh
│   ├── test.sh
│   └── deploy.sh
│
├── deployments/                # 部署配置
│   ├── docker/
│   │   └── Dockerfile
│   └── kubernetes/
│       ├── deployment.yaml
│       └── service.yaml
│
├── docs/                       # 文档
│   ├── API.md
│   └── DEVELOPMENT.md
│
├── test/                       # 测试
│   ├── integration/           # 集成测试
│   └── e2e/                   # 端到端测试
│
├── .env.example                # 环境变量示例
├── .gitignore
├── go.mod
├── go.sum
├── Makefile
└── README.md
```

## 分层架构

### 1. Handler 层（控制层）

**职责**：
- 接收 gRPC 请求
- 参数验证
- 调用 Service 层
- 返回响应

**示例**：
```go
type UserHandler struct {
    pb.UnimplementedUserServiceServer
    userService *service.UserService
    validator   *validator.UserValidator
}

func (h *UserHandler) Register(ctx context.Context, req *pb.RegisterRequest) (*pb.RegisterResponse, error) {
    // 1. 参数验证
    if err := h.validator.ValidateRegister(req); err != nil {
        return nil, status.Error(codes.InvalidArgument, err.Error())
    }
    
    // 2. 调用 Service
    user, err := h.userService.Register(ctx, req)
    if err != nil {
        return nil, err
    }
    
    // 3. 返回响应
    return &pb.RegisterResponse{
        UserId:  user.ID,
        Message: "User registered successfully",
    }, nil
}
```

### 2. Service 层（业务逻辑层）

**职责**：
- 实现业务逻辑
- 事务管理
- 调用 Repository 层
- 调用其他微服务

**示例**：
```go
type UserService struct {
    userRepo  *repository.UserRepository
    cacheRepo *repository.UserCacheRepository
    logger    *logger.Logger
}

func (s *UserService) Register(ctx context.Context, req *pb.RegisterRequest) (*model.User, error) {
    // 1. 检查用户是否存在
    exists, err := s.userRepo.ExistsByUsername(ctx, req.Username)
    if err != nil {
        return nil, err
    }
    if exists {
        return nil, errors.ErrUserAlreadyExists
    }
    
    // 2. 加密密码
    hashedPassword, err := util.HashPassword(req.Password)
    if err != nil {
        return nil, err
    }
    
    // 3. 创建用户
    user := &model.User{
        Username: req.Username,
        Email:    req.Email,
        Password: hashedPassword,
    }
    
    if err := s.userRepo.Create(ctx, user); err != nil {
        return nil, err
    }
    
    // 4. 缓存用户信息
    s.cacheRepo.Set(ctx, user)
    
    // 5. 发送欢迎邮件（异步）
    go s.sendWelcomeEmail(user.Email)
    
    return user, nil
}
```

### 3. Repository 层（数据访问层）

**职责**：
- 数据库操作
- 缓存操作
- 数据转换

**示例**：
```go
type UserRepository struct {
    db     *sql.DB
    logger *logger.Logger
}

func (r *UserRepository) Create(ctx context.Context, user *model.User) error {
    query := `
        INSERT INTO users (username, email, password, created_at)
        VALUES ($1, $2, $3, $4)
        RETURNING id
    `
    
    err := r.db.QueryRowContext(ctx, query,
        user.Username,
        user.Email,
        user.Password,
        time.Now(),
    ).Scan(&user.ID)
    
    if err != nil {
        r.logger.Error("Failed to create user", "error", err)
        return err
    }
    
    return nil
}

func (r *UserRepository) FindByID(ctx context.Context, id int64) (*model.User, error) {
    query := `
        SELECT id, username, email, avatar, created_at
        FROM users
        WHERE id = $1
    `
    
    user := &model.User{}
    err := r.db.QueryRowContext(ctx, query, id).Scan(
        &user.ID,
        &user.Username,
        &user.Email,
        &user.Avatar,
        &user.CreatedAt,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.ErrUserNotFound
    }
    if err != nil {
        return nil, err
    }
    
    return user, nil
}
```

## 核心模块设计

### 1. 配置管理

使用 Viper 管理配置，支持多环境。

```go
// pkg/config/config.go
type Config struct {
    Server   ServerConfig
    Database DatabaseConfig
    Redis    RedisConfig
    Logger   LoggerConfig
}

type ServerConfig struct {
    Port int    `mapstructure:"port"`
    Mode string `mapstructure:"mode"` // development, production
}

type DatabaseConfig struct {
    Host     string `mapstructure:"host"`
    Port     int    `mapstructure:"port"`
    User     string `mapstructure:"user"`
    Password string `mapstructure:"password"`
    Database string `mapstructure:"database"`
}

func Load(configPath string) (*Config, error) {
    viper.SetConfigFile(configPath)
    viper.AutomaticEnv()
    
    if err := viper.ReadInConfig(); err != nil {
        return nil, err
    }
    
    var config Config
    if err := viper.Unmarshal(&config); err != nil {
        return nil, err
    }
    
    return &config, nil
}
```

配置文件：
```yaml
# config/config.yaml
server:
  port: 50051
  mode: development

database:
  host: ${DB_HOST:localhost}
  port: ${DB_PORT:5432}
  user: ${DB_USER:postgres}
  password: ${DB_PASSWORD:postgres}
  database: ${DB_NAME:userdb}

redis:
  host: ${REDIS_HOST:localhost}
  port: ${REDIS_PORT:6379}
  db: 0

logger:
  level: debug
  format: json
```

### 2. 日志管理

使用结构化日志，支持多种输出格式。

```go
// pkg/logger/logger.go
type Logger struct {
    logger *zap.Logger
}

func New(config LoggerConfig) (*Logger, error) {
    var zapConfig zap.Config
    
    if config.Mode == "production" {
        zapConfig = zap.NewProductionConfig()
    } else {
        zapConfig = zap.NewDevelopmentConfig()
    }
    
    zapConfig.Level = zap.NewAtomicLevelAt(parseLevel(config.Level))
    
    logger, err := zapConfig.Build()
    if err != nil {
        return nil, err
    }
    
    return &Logger{logger: logger}, nil
}

func (l *Logger) Info(msg string, fields ...interface{}) {
    l.logger.Info(msg, toZapFields(fields...)...)
}

func (l *Logger) Error(msg string, fields ...interface{}) {
    l.logger.Error(msg, toZapFields(fields...)...)
}
```

使用示例：
```go
logger.Info("User registered", 
    "user_id", user.ID,
    "username", user.Username,
    "ip", req.IP)
```

### 3. 错误处理

统一的错误码和错误处理。

```go
// pkg/errors/errors.go
var (
    ErrUserNotFound      = NewError(10001, "User not found")
    ErrUserAlreadyExists = NewError(10002, "User already exists")
    ErrInvalidPassword   = NewError(10003, "Invalid password")
)

type Error struct {
    Code    int
    Message string
}

func (e *Error) Error() string {
    return e.Message
}

func NewError(code int, message string) *Error {
    return &Error{Code: code, Message: message}
}

// 转换为 gRPC 错误
func ToGRPCError(err error) error {
    if e, ok := err.(*Error); ok {
        return status.Error(codes.Code(e.Code), e.Message)
    }
    return status.Error(codes.Internal, "Internal server error")
}
```

### 4. 中间件

#### 日志中间件
```go
// internal/middleware/logging.go
func LoggingInterceptor(logger *logger.Logger) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
        start := time.Now()
        
        resp, err := handler(ctx, req)
        
        duration := time.Since(start)
        
        logger.Info("gRPC request",
            "method", info.FullMethod,
            "duration", duration.Milliseconds(),
            "error", err)
        
        return resp, err
    }
}
```

#### 恢复中间件
```go
// internal/middleware/recovery.go
func RecoveryInterceptor(logger *logger.Logger) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
        defer func() {
            if r := recover(); r != nil {
                logger.Error("Panic recovered",
                    "method", info.FullMethod,
                    "panic", r,
                    "stack", string(debug.Stack()))
                err = status.Error(codes.Internal, "Internal server error")
            }
        }()
        
        return handler(ctx, req)
    }
}
```

#### 追踪中间件
```go
// internal/middleware/tracing.go
func TracingInterceptor() grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
        // 从 metadata 提取 trace_id
        md, ok := metadata.FromIncomingContext(ctx)
        if !ok {
            md = metadata.New(nil)
        }
        
        traceID := md.Get("x-trace-id")
        if len(traceID) == 0 {
            traceID = []string{generateTraceID()}
        }
        
        // 注入 trace_id 到 context
        ctx = context.WithValue(ctx, "trace_id", traceID[0])
        
        return handler(ctx, req)
    }
}
```

### 5. 数据验证

```go
// internal/validator/user_validator.go
type UserValidator struct{}

func (v *UserValidator) ValidateRegister(req *pb.RegisterRequest) error {
    if len(req.Username) < 3 || len(req.Username) > 20 {
        return errors.New("username must be between 3 and 20 characters")
    }
    
    if !isValidEmail(req.Email) {
        return errors.New("invalid email format")
    }
    
    if len(req.Password) < 6 {
        return errors.New("password must be at least 6 characters")
    }
    
    return nil
}

func isValidEmail(email string) bool {
    re := regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
    return re.MatchString(email)
}
```

### 6. 后台任务

```go
// internal/worker/email_worker.go
type EmailWorker struct {
    queue  *queue.RabbitMQ
    logger *logger.Logger
}

func (w *EmailWorker) Start(ctx context.Context) error {
    return w.queue.Consume("email_queue", func(msg []byte) error {
        var emailTask EmailTask
        if err := json.Unmarshal(msg, &emailTask); err != nil {
            return err
        }
        
        return w.sendEmail(emailTask)
    })
}

func (w *EmailWorker) sendEmail(task EmailTask) error {
    w.logger.Info("Sending email", "to", task.To, "subject", task.Subject)
    // 发送邮件逻辑
    return nil
}
```

## 数据库迁移

使用 golang-migrate 管理数据库版本。

```sql
-- migrations/000001_create_users_table.up.sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    avatar VARCHAR(255),
    bio TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
```

```sql
-- migrations/000001_create_users_table.down.sql
DROP TABLE IF EXISTS users;
```

运行迁移：
```bash
migrate -path migrations -database "postgresql://user:pass@localhost:5432/db?sslmode=disable" up
```

## 测试策略

### 单元测试
```go
// internal/service/user_service_test.go
func TestUserService_Register(t *testing.T) {
    // 1. 准备测试数据
    mockRepo := &MockUserRepository{}
    service := &UserService{userRepo: mockRepo}
    
    req := &pb.RegisterRequest{
        Username: "testuser",
        Email:    "test@example.com",
        Password: "password123",
    }
    
    // 2. 执行测试
    user, err := service.Register(context.Background(), req)
    
    // 3. 验证结果
    assert.NoError(t, err)
    assert.NotNil(t, user)
    assert.Equal(t, "testuser", user.Username)
}
```

### 集成测试
```go
// test/integration/user_test.go
func TestUserIntegration(t *testing.T) {
    // 1. 启动测试数据库
    db := setupTestDB(t)
    defer teardownTestDB(t, db)
    
    // 2. 创建服务
    service := createUserService(db)
    
    // 3. 测试完整流程
    user, err := service.Register(ctx, req)
    assert.NoError(t, err)
    
    // 4. 验证数据库
    dbUser, err := service.FindByID(ctx, user.ID)
    assert.NoError(t, err)
    assert.Equal(t, user.Username, dbUser.Username)
}
```

## 总结

这个脚手架设计遵循以下原则：

1. **清晰的分层**：Handler → Service → Repository
2. **依赖注入**：便于测试和替换实现
3. **统一的错误处理**：自定义错误码
4. **完善的中间件**：日志、恢复、追踪
5. **配置管理**：支持多环境
6. **数据库迁移**：版本化管理
7. **测试友好**：单元测试、集成测试

**下一步**：实现脚手架代码和自动化生成工具。
