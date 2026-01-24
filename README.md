# uyou-api-gateway

**API Gateway 仓库** - 管理 Apache APISIX 配置和本地 Docker 开发环境

这是 **uyou 社交系统** 的 API Gateway 仓库，负责：
- 管理 Apache APISIX 网关配置
- 合并所有微服务的路由配置
- 提供本地 Docker 开发环境
- 自动同步微服务的 APISIX 路由配置

## 🏗️ 仓库架构

本项目采用**多仓库架构**，每个微服务都是独立的 Git 仓库：

```
uyou-api-gateway (本仓库)
├── 管理 APISIX 配置
├── 合并所有微服务路由配置
├── 本地 Docker 开发环境
└── services/ (本地开发目录，不提交到 Git)
    ├── user-service/    # 从 uyou-user-service 仓库克隆
    ├── order-service/   # 从 uyou-order-service 仓库克隆
    └── feed-service/   # 从 uyou-feed-service 仓库克隆

uyou-user-service (独立仓库)
├── 用户服务代码
├── proto/ 定义
└── apisix/routes.yaml  # 路由配置（自动同步到本仓库）

uyou-order-service (独立仓库)
├── 订单服务代码
├── proto/ 定义
└── apisix/routes.yaml  # 路由配置（自动同步到本仓库）

uyou-feed-service (独立仓库)
├── 动态服务代码
├── proto/ 定义
└── apisix/routes.yaml  # 路由配置（自动同步到本仓库）
```

## 📐 架构图

```
┌─────────────┐
│   客户端     │ (REST/JSON)
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│         Apache APISIX Gateway (本仓库管理)          │
│  - JWT 认证                                          │
│  - 限流/熔断                                         │
│  - CORS                                             │
│  - 日志/TraceID                                      │
│  - REST → gRPC 转码                                  │
└──────┬──────────────────┬───────────────────┬──────┘
       │                  │                   │
       ▼                  ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   用户服务   │    │   订单服务   │    │   动态服务   │
│ (独立仓库)   │    │ (独立仓库)   │    │ (独立仓库)   │
│             │    │             │    │             │
│ PostgreSQL  │    │ PostgreSQL  │    │ MongoDB     │
│ Redis       │    │ Redis       │    │ Redis       │
└─────────────┘    └─────────────┘    └─────────────┘
```

## 🚀 快速开始

### 前置要求

- Docker 20.10+
- Docker Compose 2.0+
- Make (可选)
- Git

### 1. 克隆本仓库

```bash
git clone https://github.com/your-org/uyou-api-gateway.git
cd uyou-api-gateway
```

### 2. 准备本地开发环境（可选）

如果需要本地开发微服务，可以克隆微服务仓库到 `services/` 目录：

```bash
# 克隆微服务到本地（用于本地开发）
mkdir -p services
cd services
git clone https://github.com/your-org/uyou-user-service.git user-service
git clone https://github.com/your-org/uyou-order-service.git order-service
git clone https://github.com/your-org/uyou-feed-service.git feed-service
cd ..
```

> **注意**: `services/` 目录不会被提交到 Git（已在 `.gitignore` 中排除）

### 3. 启动所有服务

```bash
# 启动 Docker 环境（包括数据库、Redis、etcd、APISIX）
make run
# 或
docker compose up -d
```

### 4. 初始化 APISIX 路由配置

```bash
# 合并所有微服务的路由配置并部署到 APISIX
make update-apisix-merge
```

### 5. 测试 API

```bash
# 测试用户注册
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "email": "demo@example.com",
    "password": "demo123"
  }'
```

## 📚 文档

- **[SETUP-GUIDE.md](./SETUP-GUIDE.md)** - 完整设置指南，包括 Git Hook 自动同步配置
- **[RUN.md](./RUN.md)** - 运行指南，包括详细步骤、故障排查、常用命令
- **[TUTORIAL.md](./TUTORIAL.md)** - 完整教程，包括架构设计、API 文档、开发指南
- **[APISIX-CONFIG-GUIDE.md](./APISIX-CONFIG-GUIDE.md)** - APISIX 配置管理详细指南
- **[QUICK-REFERENCE.md](./QUICK-REFERENCE.md)** - 配置管理快速参考

## 🔧 常用命令

### 服务管理

```bash
make run          # 启动所有服务
make stop         # 停止所有服务
make restart      # 重启服务
make logs         # 查看日志
```

### APISIX 配置管理

```bash
# 合并所有微服务的路由配置并部署到 APISIX
make update-apisix-merge

# 验证 APISIX 配置
make validate-config

# 从本地 services/ 目录同步路由配置（如果本地有微服务代码）
make sync-routes
```

### 本地开发（如果 services/ 目录有微服务代码）

```bash
# 生成所有微服务的 Proto 代码
make proto

# 从 proto 生成路由配置
make generate-route SERVICE=user

# 构建所有微服务
make build
```

### 查看帮助

```bash
make help
```

## 🔄 路由配置自动同步

每个微服务仓库都配置了 Git Hook，当微服务提交 `apisix/routes.yaml` 时，会自动同步到本仓库：

1. **微服务开发者**修改 `apisix/routes.yaml` 并提交
2. **Git Hook 自动触发**，将路由配置同步到 `uyou-api-gateway` 仓库
3. **自动提交**到 `apisix/config/routes/{service}-routes.yaml`
4. **手动或自动部署**到 APISIX

详细设置请参考：[SETUP-GUIDE.md](./SETUP-GUIDE.md)

## 📁 项目结构

```
uyou-api-gateway/
├── apisix/                    # APISIX 配置
│   └── config/
│       ├── config.yaml       # APISIX 主配置
│       ├── apisix.yaml        # 路由配置（传统方式，可选）
│       └── routes/           # 微服务路由配置片段
│           ├── user-routes.yaml    # 从 uyou-user-service 自动同步
│           ├── order-routes.yaml   # 从 uyou-order-service 自动同步
│           └── feed-routes.yaml    # 从 uyou-feed-service 自动同步
├── scripts/                   # 工具脚本
│   ├── merge-apisix-configs.sh    # 合并并部署路由配置
│   ├── sync-routes.sh            # 从本地 services/ 同步路由
│   ├── validate-config.sh         # 验证配置
│   └── git-hooks/                 # Git Hook 脚本
│       ├── post-commit-sync-routes.sh  # 自动同步 Hook
│       └── install-hook.sh            # Hook 安装脚本
├── services/                  # 本地开发目录（不提交到 Git）
│   ├── user-service/          # 从 uyou-user-service 克隆
│   ├── order-service/         # 从 uyou-order-service 克隆
│   └── feed-service/          # 从 uyou-feed-service 克隆
├── docker-compose.yml         # Docker 编排文件
├── Makefile                   # 构建和管理命令
└── README.md                  # 本文件
```

## 🌐 访问地址

- **APISIX Gateway**: http://localhost:9080
- **APISIX Admin API**: http://localhost:9180

## 📖 核心概念

### 多仓库架构

- **独立开发**: 每个微服务都是独立的 Git 仓库，可以独立开发、测试、部署
- **配置集中**: API Gateway 仓库集中管理所有路由配置
- **自动同步**: 通过 Git Hook 自动同步微服务的路由配置

### REST to gRPC 转码

APISIX 自动将客户端的 REST/JSON 请求转换为 gRPC 调用：

```
客户端 REST 请求 → APISIX 转码 → gRPC 服务调用
```

### 微服务划分

- **User Service**: 用户认证、注册、个人资料管理
- **Order Service**: 订单创建、查询、状态更新
- **Feed Service**: 动态发布、时间线、点赞评论

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

---

**Happy Learning! 🎉**
