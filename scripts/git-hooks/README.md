# Git Hooks 自动同步路由配置

这个方案允许微服务作为独立仓库，通过 Git Hook 自动将路由配置同步到主仓库。

## 架构

```
微服务仓库 (独立)
├── apisix/
│   └── routes.yaml          # 路由配置
└── .git/hooks/
    └── post-commit          # 自动同步脚本

主仓库 (uyou-Infrastructure)
└── apisix/config/routes/
    ├── user-routes.yaml     # 自动同步
    ├── order-routes.yaml    # 自动同步
    └── feed-routes.yaml     # 自动同步
```

## 设置步骤

### 1. 在微服务仓库中安装 Hook

**方式 1: 使用安装脚本（推荐）**

```bash
# 从主仓库运行安装脚本
cd /Users/sam/Projects/2026/uyou-Infrastructure
./scripts/git-hooks/install-hook.sh /path/to/user-service user
./scripts/git-hooks/install-hook.sh /path/to/order-service order
./scripts/git-hooks/install-hook.sh /path/to/feed-service feed
```

**方式 2: 手动安装**

```bash
# 进入微服务仓库
cd /path/to/user-service

# 复制 hook 脚本
cp /path/to/uyou-Infrastructure/scripts/git-hooks/post-commit-sync-routes.sh .git/hooks/post-commit
chmod +x .git/hooks/post-commit

# 创建配置文件（可选，推荐）
cat > .infra-sync-config <<EOF
INFRA_REPO_PATH=/Users/sam/Projects/2026/uyou-Infrastructure
SERVICE_NAME=user
AUTO_PUSH=false
EOF
```

### 2. 配置服务名称

Hook 会自动从仓库名称推断服务名称，规则：
- `user-service` → `user`
- `uyou-user-service` → `user`
- `order-service` → `order`

如果自动推断不正确，可以在 `.infra-sync-config` 中手动设置：

```bash
SERVICE_NAME=user
```

### 3. 测试 Hook

```bash
# 修改路由配置
vim apisix/routes.yaml

# 提交更改
git add apisix/routes.yaml
git commit -m "update routes"

# Hook 会自动：
# 1. 检测到 routes.yaml 的更改
# 2. 复制到主仓库的 apisix/config/routes/user-routes.yaml
# 3. 在主仓库中提交更改
```

## 配置选项

### 环境变量

- `INFRA_REPO_PATH`: 主仓库路径（必需）
- `SERVICE_NAME`: 服务名称（可选，会自动推断）
- `AUTO_PUSH`: 是否自动推送（默认: false）

### 配置文件 `.infra-sync-config`

在微服务仓库根目录创建此文件：

```bash
INFRA_REPO_PATH=/Users/sam/Projects/2026/uyou-Infrastructure
SERVICE_NAME=user
AUTO_PUSH=false
```

## 工作流程

1. **开发者在微服务仓库中修改路由配置**
   ```bash
   vim apisix/routes.yaml
   git add apisix/routes.yaml
   git commit -m "update routes"
   ```

2. **Git Hook 自动触发**
   - 检测 `apisix/routes.yaml` 是否在本次提交中
   - 如果修改了，则同步到主仓库

3. **主仓库自动更新**
   - 文件复制到 `apisix/config/routes/{service}-routes.yaml`
   - 自动提交更改
   - 可选：自动推送到远程

## 优势

✅ **简单**: 不需要 Git Submodule，微服务完全独立  
✅ **自动化**: 提交后自动同步，无需手动操作  
✅ **灵活**: 可以控制是否自动推送  
✅ **可追溯**: 每次同步都记录来源提交哈希  

## 注意事项

1. **首次设置**: 需要手动配置 `INFRA_REPO_PATH`
2. **自动推送**: 默认不自动推送，需要手动执行 `git push`
3. **冲突处理**: 如果主仓库有未提交的更改，需要先解决冲突
4. **权限**: 确保有主仓库的写入权限

## 故障排查

### Hook 没有执行

```bash
# 检查 hook 是否存在且可执行
ls -la .git/hooks/post-commit
chmod +x .git/hooks/post-commit
```

### 找不到主仓库

```bash
# 检查配置
cat .infra-sync-config
# 或
echo $INFRA_REPO_PATH
```

### 同步失败

```bash
# 查看 hook 输出
git commit -m "test"  # 会显示 hook 的输出

# 手动运行 hook 测试
.git/hooks/post-commit
```
