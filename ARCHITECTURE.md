# 架构说明

## 🏗️ 多仓库架构

本项目采用**多仓库架构**，每个微服务都是独立的 Git 仓库。

### 仓库结构

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
└── apisix/routes.yaml  # 路由配置（自动同步到 uyou-api-gateway）

uyou-order-service (独立仓库)
├── 订单服务代码
├── proto/ 定义
└── apisix/routes.yaml  # 路由配置（自动同步到 uyou-api-gateway）

uyou-feed-service (独立仓库)
├── 动态服务代码
├── proto/ 定义
└── apisix/routes.yaml  # 路由配置（自动同步到 uyou-api-gateway）
```

## 🔄 工作流程

### 路由配置自动同步

```
1. 开发者在微服务仓库中修改 apisix/routes.yaml
   ↓
2. 提交更改（git commit）
   ↓
3. Git Hook 自动触发
   ↓
4. 自动同步到 uyou-api-gateway/apisix/config/routes/{service}-routes.yaml
   ↓
5. 在 uyou-api-gateway 中自动提交
   ↓
6. 使用 make update-apisix-merge 合并并部署到 APISIX
```

### 本地开发流程

```
1. 克隆微服务到 services/ 目录（本地开发）
   ↓
2. 修改代码和路由配置
   ↓
3. 在微服务仓库中提交（触发自动同步）
   ↓
4. 或使用 make sync-routes 手动同步
   ↓
5. 使用 make update-apisix-merge 部署
```

## 📁 目录说明

### uyou-api-gateway 仓库

- `apisix/config/` - APISIX 配置文件
  - `config.yaml` - APISIX 主配置
  - `routes/` - 微服务路由配置片段（自动同步）
- `scripts/` - 工具脚本
  - `merge-apisix-configs.sh` - 合并并部署路由配置
  - `git-hooks/` - Git Hook 脚本
- `services/` - 本地开发目录（不提交到 Git）
- `docker-compose.yml` - Docker 编排文件

### 微服务仓库

- `proto/` - Proto 定义文件
- `apisix/routes.yaml` - APISIX 路由配置（自动同步）
- `main.go` - 服务入口
- `go.mod` - Go 模块
- `Makefile` - 构建脚本（从模板复制）

## 🔧 关键命令

### 微服务仓库

```bash
make proto    # 生成 Proto 代码
make apisix   # 生成 APISIX 路由配置
make build    # 构建服务
```

### uyou-api-gateway 仓库

```bash
make update-apisix-merge  # 合并并部署路由配置
make sync-routes          # 从本地 services/ 同步路由
make validate-config      # 验证配置
make run                  # 启动 Docker 环境
```

## 📚 相关文档

- [README.md](./README.md) - 项目概述
- [SETUP-GUIDE.md](./SETUP-GUIDE.md) - 详细设置指南
- [RUN.md](./RUN.md) - 运行指南
- [TUTORIAL.md](./TUTORIAL.md) - 完整教程
