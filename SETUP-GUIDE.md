# 设置指南

本指南介绍如何设置 **uyou 社交系统** 的多仓库架构。

## 🏗️ 架构概览

本项目采用**多仓库架构**，每个微服务都是独立的 Git 仓库：

- **uyou-api-gateway** (本仓库) - API Gateway 仓库，管理 APISIX 配置
- **uyou-user-service** - 用户服务（独立仓库）
- **uyou-order-service** - 订单服务（独立仓库）
- **uyou-feed-service** - 动态服务（独立仓库）

### 工作流程

```
微服务仓库 (独立)
├── apisix/routes.yaml          # 路由配置
└── .git/hooks/post-commit      # Git Hook

    提交时自动触发
           │
           ▼
uyou-api-gateway 仓库
└── apisix/config/routes/
    ├── user-routes.yaml        # 自动同步
    ├── order-routes.yaml      # 自动同步
    └── feed-routes.yaml        # 自动同步

    合并并部署
           │
           ▼
    Apache APISIX (etcd)
```

---

## 方案 A: Git Hook 自动同步（推荐）⭐

这是最简单的方案：微服务作为独立仓库，通过 Git Hook 自动同步路由配置。

### 优势

- ✅ **简单**: 不需要 Git Submodule，微服务完全独立
- ✅ **自动化**: 提交后自动同步，无需手动操作
- ✅ **灵活**: 可以控制是否自动推送
- ✅ **可追溯**: 每次同步都记录来源提交哈希

### 步骤 1: 准备微服务仓库

确保每个微服务仓库都有以下结构：

```bash
uyou-user-service/
├── proto/
│   └── user.proto
├── apisix/
│   └── routes.yaml    # 必须存在
├── main.go
├── go.mod
└── Makefile          # 从模板复制，见步骤 2
```

### 步骤 2: 设置微服务仓库的 Makefile

从 `uyou-api-gateway` 仓库复制 Makefile 模板：

```bash
# 进入微服务仓库
cd /path/to/uyou-user-service

# 复制 Makefile 模板
cp /path/to/uyou-api-gateway/scripts/templates/service-Makefile Makefile

# 编辑 Makefile，修改 SERVICE_NAME（如果需要）
# SERVICE_NAME ?= user
```

现在可以使用以下命令：

```bash
# 生成 Proto 代码
make proto

# 生成 APISIX 路由配置（模板）
make apisix

# 构建服务
make build
```

### 步骤 3: 安装 Git Hook

在每个微服务仓库中安装自动同步 Hook：

**方式 1: 使用安装脚本（推荐）**

```bash
# 从 uyou-api-gateway 仓库运行安装脚本
cd /path/to/uyou-api-gateway
./scripts/git-hooks/install-hook.sh /path/to/uyou-user-service user
./scripts/git-hooks/install-hook.sh /path/to/uyou-order-service order
./scripts/git-hooks/install-hook.sh /path/to/uyou-feed-service feed
```

**方式 2: 手动安装**

```bash
# 进入微服务仓库
cd /path/to/uyou-user-service

# 复制 hook 脚本
cp /path/to/uyou-api-gateway/scripts/git-hooks/post-commit-sync-routes.sh .git/hooks/post-commit
chmod +x .git/hooks/post-commit

# 创建配置文件
cat > .infra-sync-config <<EOF
INFRA_REPO_PATH=/path/to/uyou-api-gateway
SERVICE_NAME=user
AUTO_PUSH=false
EOF

# 添加到 .gitignore（配置文件包含本地路径，不应提交）
echo ".infra-sync-config" >> .gitignore
```

**配置说明：**
- `INFRA_REPO_PATH`: uyou-api-gateway 仓库的路径
- `SERVICE_NAME`: 服务名称（如：user, order, feed），会自动从仓库名推断
- `AUTO_PUSH`: 是否自动推送到远程（默认: false，建议手动推送）

### 步骤 4: 创建 APISIX 路由配置

在微服务仓库中创建或生成路由配置：

```bash
# 方式 1: 使用 Makefile 生成模板
make apisix

# 方式 2: 手动创建
mkdir -p apisix
vim apisix/routes.yaml
```

路由配置示例：

```yaml
routes:
  - uri: /api/v1/users/register
    name: user-register
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

### 步骤 5: 测试自动同步

```bash
# 在微服务仓库中修改路由配置
vim apisix/routes.yaml

# 提交更改（Hook 会自动触发）
git add apisix/routes.yaml
git commit -m "update routes"

# Hook 会自动：
# 1. 检测到 routes.yaml 的更改
# 2. 复制到 uyou-api-gateway 的 apisix/config/routes/user-routes.yaml
# 3. 在 uyou-api-gateway 中提交更改
```

### 步骤 6: 验证同步结果

```bash
# 进入 uyou-api-gateway 仓库
cd /path/to/uyou-api-gateway

# 查看同步的路由配置
ls -la apisix/config/routes/

# 查看最新提交
git log --oneline -5
```

### 步骤 7: 部署到 APISIX

```bash
# 在 uyou-api-gateway 仓库中
# 合并所有路由配置并部署到 APISIX
make update-apisix-merge

# 验证配置
make validate-config
```

### 工作流程总结

1. **开发者在微服务仓库中修改路由配置** → 提交更改
2. **Git Hook 自动触发** → 检测到 `apisix/routes.yaml` 的更改
3. **自动同步到 uyou-api-gateway** → 复制到 `apisix/config/routes/{service}-routes.yaml`
4. **自动提交** → 在 uyou-api-gateway 中创建提交记录
5. **手动推送**（可选） → 推送到远程仓库
6. **部署到 APISIX** → 使用 `make update-apisix-merge` 合并并部署

### 故障排查

**Hook 没有执行**

```bash
# 检查 hook 是否存在且可执行
ls -la .git/hooks/post-commit
chmod +x .git/hooks/post-commit

# 检查配置
cat .infra-sync-config

# 手动测试 hook
.git/hooks/post-commit
```

**找不到主仓库**

```bash
# 检查配置
cat .infra-sync-config
# 或
echo $INFRA_REPO_PATH

# 更新配置
vim .infra-sync-config
```

**同步失败**

```bash
# 查看 hook 输出
git commit -m "test"  # 会显示 hook 的输出

# 检查主仓库状态
cd /path/to/uyou-api-gateway
git status
```

更多详细信息请参考：`scripts/git-hooks/README.md`

---

## 方案 B: 本地开发环境设置

如果需要本地开发微服务，可以在 `uyou-api-gateway` 仓库的 `services/` 目录中克隆微服务代码。

### 步骤 1: 克隆微服务到本地

```bash
# 进入 uyou-api-gateway 仓库
cd /path/to/uyou-api-gateway

# 克隆微服务到 services/ 目录（用于本地开发）
mkdir -p services
cd services
git clone https://github.com/your-org/uyou-user-service.git user-service
git clone https://github.com/your-org/uyou-order-service.git order-service
git clone https://github.com/your-org/uyou-feed-service.git feed-service
cd ..
```

> **注意**: `services/` 目录不会被提交到 Git（已在 `.gitignore` 中排除）

### 步骤 2: 本地开发

```bash
# 生成所有微服务的 Proto 代码
make proto

# 从本地 services/ 同步路由配置到 apisix/config/routes/
make sync-routes

# 构建所有微服务
make build
```

### 步骤 3: 部署

```bash
# 合并并部署路由配置
make update-apisix-merge
```

---

## 方案 C: CI/CD 自动化设置

### 步骤 1: 准备 GitHub Secrets

在 GitHub 仓库设置中添加以下 Secrets：

#### 开发环境（可选）

```
APISIX_ADMIN_URL_DEV=http://localhost:9180
APISIX_ADMIN_KEY_DEV=edd1c9f034335f136f87ad84b625c8f1
```

#### staging 环境

```
APISIX_ADMIN_URL_STAGING=http://apisix-staging:9180
APISIX_ADMIN_KEY_STAGING=your-staging-key
```

#### 生产环境

```
APISIX_ADMIN_URL_PROD=http://apisix-prod:9180
APISIX_ADMIN_KEY_PROD=your-production-key
```

### 步骤 2: 配置 GitHub Actions

GitHub Actions 工作流已配置在 `.github/workflows/deploy-apisix.yml`。

当 `apisix/config/routes/` 目录有更改时，会自动：
1. 合并所有路由配置
2. 验证配置
3. 部署到 APISIX（根据环境）

### 步骤 3: 触发部署

```bash
# 路由配置更改会自动触发部署
git add apisix/config/routes/
git commit -m "chore: update routes"
git push
```

---

## 快速参考

### 微服务仓库操作

```bash
# 生成 Proto 代码
make proto

# 生成 APISIX 路由配置
make apisix

# 构建服务
make build
```

### uyou-api-gateway 仓库操作

```bash
# 合并并部署路由配置
make update-apisix-merge

# 从本地 services/ 同步路由（本地开发用）
make sync-routes

# 验证配置
make validate-config

# 启动 Docker 环境
make run
```

### Git Hook 管理

```bash
# 安装 Hook 到微服务仓库
./scripts/git-hooks/install-hook.sh <微服务路径> <服务名称>

# 查看 Hook 文档
cat scripts/git-hooks/README.md
```

---

## 常见问题

### Q: 为什么 services/ 目录不提交到 Git？

A: `services/` 目录用于本地开发，每个微服务都是独立的 Git 仓库。提交到 Git 会导致仓库过大，且不利于独立开发。

### Q: 如何更新微服务的路由配置？

A: 在微服务仓库中修改 `apisix/routes.yaml` 并提交，Git Hook 会自动同步到 `uyou-api-gateway`。

### Q: 如何手动同步路由配置？

A: 如果本地有微服务代码，可以使用 `make sync-routes`。否则，路由配置通过 Git Hook 自动同步。

### Q: 如何禁用自动推送？

A: 在 `.infra-sync-config` 中设置 `AUTO_PUSH=false`（默认值），然后手动推送。

### Q: 多个开发者如何协作？

A: 每个开发者克隆各自的微服务仓库，修改路由配置后提交。Git Hook 会自动同步到 `uyou-api-gateway`，然后推送到远程即可。

---

**Happy Coding! 🎉**
