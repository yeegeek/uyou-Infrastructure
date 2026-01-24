# APISIX 配置管理快速参考

## 📌 问题快速解答

### Q1: Proto 文件应该放在哪里？

**A: 每个微服务仓库管理自己的 proto 文件**

- **多仓库架构**: 每个微服务仓库有自己的 `proto/` 目录 ✅（当前方案）
- **本地开发**: 可以在 `uyou-api-gateway/services/` 目录克隆微服务代码进行本地开发

### Q2: 微服务和 APISIX 不在同一目录，如何生成配置？

**A: 使用 Admin API 动态推送**

```bash
# 方式 1: 使用合并脚本（推荐）
./scripts/merge-apisix-configs.sh

# 方式 2: 使用 Makefile
make update-apisix-merge
```

### Q3: 是否需要每个微服务生成不同的 apisix.yaml？

**A: 不需要！使用配置合并策略**

- ❌ 不推荐：每个服务独立配置文件
- ✅ 推荐：每个服务提供配置片段，统一合并部署

### Q4: 开发环境和生产环境如何管理配置？

**A: 环境分离 + 配置模板**

- **开发环境**: 静态配置文件 `apisix/config/apisix.yaml`
- **生产环境**: Admin API + CI/CD 自动部署

---

## 🚀 快速开始

### 单仓库开发（当前方案）

```bash
# 1. 修改 proto 文件
vim proto/user.proto

# 2. 生成代码并更新配置
make proto-update

# 3. 重启服务
make restart
```

### 多仓库开发（推荐）

```bash
# 1. 在微服务仓库中修改路由配置并提交
# Git Hook 会自动同步到 uyou-api-gateway

# 2. 在 uyou-api-gateway 仓库中部署
make update-apisix-merge
```

---

## 🔧 常用命令

### 基础命令

```bash
make proto              # 生成 Proto 代码
make update-apisix      # 更新 APISIX 配置（传统方式）
make update-apisix-merge # 更新 APISIX 配置（合并方式）
make proto-update       # 完整更新流程
```

### 多仓库场景

```bash
# 在 uyou-api-gateway 仓库中
make update-apisix-merge  # 合并并部署路由配置（推荐）
make sync-routes         # 从本地 services/ 同步路由（本地开发用）
make validate-config     # 验证配置
```

### 查看帮助

```bash
make help              # 查看所有可用命令
```

---

## 📝 配置示例

### 单个路由配置

```yaml
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
        allow_headers: "*"
```

### 环境变量配置

```bash
# .env 文件
APISIX_ENV=dev
APISIX_ADMIN_URL=http://localhost:9180
APISIX_ADMIN_KEY=edd1c9f034335f136f87ad84b625c8f1

# 生产环境
APISIX_ENV=prod
APISIX_ADMIN_URL=http://apisix-prod:9180
APISIX_ADMIN_KEY=${PROD_ADMIN_KEY}
```

---

## 🎯 最佳实践

### 1. Proto 文件管理

- ✅ 使用版本控制
- ✅ 建立 API 变更规范
- ✅ 使用 Git Submodule 或独立仓库共享

### 2. 配置管理

- ✅ 开发环境：静态配置文件
- ✅ 生产环境：Admin API + CI/CD
- ✅ 配置版本化（Git）
- ✅ 配置验证（部署前检查）

### 3. 团队协作

- ✅ 明确配置职责
- ✅ 建立配置审查流程
- ✅ 文档化配置变更

---

## 📚 相关文档

- [SETUP-GUIDE.md](./SETUP-GUIDE.md) - 详细设置指南（Git Submodule 和 CI/CD）
- [APISIX-CONFIG-GUIDE.md](./APISIX-CONFIG-GUIDE.md) - 配置管理详细指南
- [RUN.md](./RUN.md) - 运行指南
- [TUTORIAL.md](./TUTORIAL.md) - 完整教程
