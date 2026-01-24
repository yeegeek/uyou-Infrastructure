# 微服务仓库模板说明

这些模板文件用于创建新的微服务仓库。

## 文件说明

- `service-Makefile` - 微服务仓库的 Makefile 模板

## 使用方法

### 1. 创建新的微服务仓库

```bash
# 创建新仓库
mkdir uyou-new-service
cd uyou-new-service
git init

# 复制 Makefile 模板
cp /path/to/uyou-api-gateway/scripts/templates/service-Makefile Makefile

# 修改 Makefile 中的 SERVICE_NAME
# 将 SERVICE_NAME ?= user 改为 SERVICE_NAME ?= new-service
```

### 2. 创建项目结构

```bash
# 创建目录结构
mkdir -p proto apisix

# 创建 proto 文件
touch proto/new-service.proto

# 创建 apisix 路由配置（可选，可以通过 make apisix 生成）
mkdir -p apisix
touch apisix/routes.yaml
```

### 3. 使用 Makefile

```bash
# 生成 Proto 代码
make proto

# 生成 APISIX 路由配置
make apisix

# 构建服务
make build

# 查看帮助
make help
```

### 4. 安装 Git Hook（自动同步路由配置）

```bash
# 从 uyou-api-gateway 仓库安装 Hook
/path/to/uyou-api-gateway/scripts/git-hooks/install-hook.sh $(pwd) new-service
```

### 5. 提交并测试自动同步

```bash
# 修改 apisix/routes.yaml
vim apisix/routes.yaml

# 提交更改（Hook 会自动同步到 uyou-api-gateway）
git add apisix/routes.yaml
git commit -m "update routes"
```

## Makefile 变量说明

- `SERVICE_NAME` - 服务名称（如：user, order, feed）
- `PROTO_FILE` - Proto 文件路径（默认: `proto/$(SERVICE_NAME).proto`）
- `PROTO_DIR` - Proto 目录（默认: `proto`）
- `APISIX_ROUTES_FILE` - APISIX 路由配置文件路径（默认: `apisix/routes.yaml`）

## 项目结构示例

```
uyou-user-service/
├── proto/
│   └── user.proto           # Proto 定义
├── apisix/
│   └── routes.yaml         # APISIX 路由配置（自动同步到 uyou-api-gateway）
├── main.go                  # 服务入口
├── go.mod                   # Go 模块
├── Makefile                 # 构建脚本（从模板复制）
└── .infra-sync-config      # Git Hook 配置（自动生成）
```
