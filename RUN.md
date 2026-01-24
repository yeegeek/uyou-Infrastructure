# 项目运行指南

本文档提供项目的完整运行步骤，从环境准备到服务启动，再到测试验证。

## 📋 目录

- [前置要求](#前置要求)
- [快速开始](#快速开始)
- [详细步骤](#详细步骤)
- [验证服务](#验证服务)
- [常用命令](#常用命令)
- [故障排查](#故障排查)
- [停止服务](#停止服务)

---

## 前置要求

### 必需软件

- **Docker** 20.10+ 
- **Docker Compose** 2.0+
- **Make** (可选，用于快捷命令)

### 端口占用检查

确保以下端口未被占用：

| 端口 | 服务 |
|------|------|
| 9080 | APISIX Gateway (HTTP) |
| 9443 | APISIX Gateway (HTTPS) |
| 9180 | APISIX Admin API |
| 50051 | User Service (gRPC) |
| 50052 | Order Service (gRPC) |
| 50053 | Feed Service (gRPC) |
| 5432 | PostgreSQL |
| 27017 | MongoDB |
| 6379 | Redis |
| 2379 | etcd |

检查端口占用：
```bash
# macOS/Linux
netstat -tlnp | grep -E '9080|50051|50052|50053|5432|27017|6379|2379'

# 或使用 lsof
lsof -i :9080
```

---

## 快速开始

### 5 分钟快速体验

```bash
# 1. 克隆仓库（如果还没有）
git clone https://github.com/yeegeek/uyou-Infrastructure.git
cd uyou-Infrastructure

# 2. 启动所有服务
docker compose up -d

# 3. 等待服务启动（约 1-2 分钟）
docker compose ps

# 4. 初始化 APISIX 路由配置（重要！）
./scripts/init-apisix-routes.sh

# 5. 测试用户注册
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "email": "demo@example.com",
    "password": "demo123"
  }'
```

---

## 详细步骤

### 步骤 1: 启动所有服务

```bash
# 使用 Docker Compose 启动
docker compose up -d

# 或使用 Makefile
make run
```

**启动的服务包括：**
- PostgreSQL (用户和订单数据)
- MongoDB (动态数据)
- Redis (缓存)
- etcd (APISIX 配置中心)
- User Service (用户服务)
- Order Service (订单服务)
- Feed Service (动态服务)
- APISIX Gateway (API 网关)

### 步骤 2: 检查服务状态

```bash
docker compose ps
```

**预期输出：**
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

**如果服务状态不是 `healthy` 或 `running`，请等待 1-2 分钟后再检查。**

### 步骤 3: 初始化 APISIX 路由配置

**⚠️ 重要：首次启动必须运行此步骤！**

```bash
./scripts/init-apisix-routes.sh
```

**这个脚本会：**
- 创建 Proto 定义到 etcd
- 创建路由配置到 etcd
- 配置 gRPC 转码插件
- 配置 CORS 跨域支持

**如果脚本执行失败：**
1. 检查 APISIX 是否已启动：`docker compose ps apisix`
2. 等待 APISIX 完全启动（约 30 秒）
3. 检查 Admin API：`curl http://localhost:9180/apisix/admin/routes`

### 步骤 4: 验证服务

参见 [验证服务](#验证服务) 章节。

---

## 验证服务

### 访问网关和管理接口

- **APISIX Gateway**: http://localhost:9080
  - 所有 API 请求都通过此网关

- **APISIX Admin API**: http://localhost:9180
  - 用于配置路由、查看配置等
  - 使用 Admin API Key 进行认证

### 测试用户服务

```bash
# 1. 用户注册
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "email": "demo@example.com",
    "password": "demo123"
  }'

# 预期响应：
# {"user_id":1,"message":"User registered successfully"}

# 2. 用户登录
curl -X POST http://localhost:9080/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "password": "demo123"
  }'

# 预期响应：
# {"token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...","user_id":1,"username":"demo"}

# 3. 获取用户信息（替换 USER_ID）
curl -X GET http://localhost:9080/api/v1/users/1
```

### 测试订单服务

```bash
# 创建订单（替换 USER_ID 为上一步返回的 user_id）
curl -X POST http://localhost:9080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 1,
    "items": [
      {
        "product_id": 1001,
        "product_name": "测试商品",
        "quantity": 2,
        "price": 99.99
      }
    ],
    "total_amount": 199.98
  }'
```

### 测试动态服务

```bash
# 创建动态
curl -X POST http://localhost:9080/api/v1/feeds \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 1,
    "content": "我的第一条动态！",
    "images": ["https://example.com/image.jpg"],
    "location": "北京"
  }'
```

### 使用测试脚本

```bash
# 运行完整的 API 测试脚本
./scripts/test-api.sh
```

---

## 常用命令

### 服务管理

```bash
# 启动所有服务
make run
# 或
docker compose up -d

# 停止所有服务
make stop
# 或
docker compose down

# 重启服务
make restart
# 或
docker compose restart

# 查看服务状态
docker compose ps

# 查看日志
make logs
# 或
docker compose logs -f

# 查看特定服务日志
docker compose logs -f user-service
docker compose logs -f apisix
```

### Proto 文件管理

```bash
# 生成 Proto 代码
make proto

# 更新 APISIX 配置
make update-apisix

# 完整更新（生成代码 + 更新配置）
make proto-update

# 清理生成的文件
make clean
```

### 数据库操作

```bash
# 连接 PostgreSQL
docker exec -it uyou-postgres psql -U postgres -d userdb

# 连接 MongoDB
docker exec -it uyou-mongodb mongosh -u root -p example

# 连接 Redis
docker exec -it uyou-redis redis-cli
```

### APISIX 操作

```bash
# 查看 APISIX 访问日志
docker exec -it uyou-apisix tail -f /usr/local/apisix/logs/access.log

# 查看 etcd 配置
docker exec -it uyou-etcd etcdctl get --prefix /apisix

# 测试 Admin API
curl http://localhost:9180/apisix/admin/routes
```

---

## 故障排查

### 问题 1: 服务启动失败

**症状：** `docker compose ps` 显示服务状态为 `unhealthy` 或 `exited`

**排查步骤：**

1. **检查端口占用**
   ```bash
   lsof -i :9080
   lsof -i :50051
   ```

2. **查看服务日志**
   ```bash
   docker compose logs user-service
   docker compose logs apisix
   ```

3. **检查 Docker 资源**
   ```bash
   docker system df
   docker ps -a
   ```

4. **重启服务**
   ```bash
   docker compose down
   docker compose up -d
   ```

### 问题 2: API 返回 502 错误

**症状：** 请求 API 返回 `502 Bad Gateway`

**可能原因：**
- 后端服务未启动
- APISIX 路由配置未初始化
- 服务健康检查未通过

**解决方案：**

1. **检查服务状态**
   ```bash
   docker compose ps
   ```

2. **重新初始化路由**
   ```bash
   ./scripts/init-apisix-routes.sh
   ```

3. **等待服务完全启动**
   ```bash
   # 等待 1-2 分钟，然后重试
   docker compose ps
   ```

### 问题 3: 数据库连接失败

**症状：** 服务日志显示数据库连接错误

**排查步骤：**

1. **检查数据库健康状态**
   ```bash
   docker compose ps postgres
   docker compose ps mongodb
   ```

2. **手动连接测试**
   ```bash
   # PostgreSQL
   docker exec -it uyou-postgres psql -U postgres -d userdb
   
   # MongoDB
   docker exec -it uyou-mongodb mongosh -u root -p example
   ```

3. **检查环境变量**
   ```bash
   docker exec uyou-user-service env | grep DB_
   ```

### 问题 4: APISIX 路由不生效

**症状：** 请求返回 404 或路由未匹配

**解决方案：**

1. **检查路由配置**
   ```bash
   curl http://localhost:9180/apisix/admin/routes
   ```

2. **检查 etcd 配置**
   ```bash
   docker exec -it uyou-etcd etcdctl get --prefix /apisix
   ```

3. **重新初始化路由**
   ```bash
   ./scripts/init-apisix-routes.sh
   ```

4. **重启 APISIX**
   ```bash
   docker compose restart apisix
   ```

### 问题 5: Proto 文件更新后不生效

**症状：** 修改 proto 文件后，服务仍使用旧接口

**解决方案：**

1. **重新生成代码和配置**
   ```bash
   make proto-update
   ```

2. **重启相关服务**
   ```bash
   docker compose restart user-service
   docker compose restart order-service
   docker compose restart feed-service
   ```

### 问题 6: 内存或磁盘空间不足

**症状：** Docker 容器无法启动或频繁重启

**解决方案：**

1. **清理未使用的资源**
   ```bash
   docker system prune -a
   ```

2. **检查磁盘空间**
   ```bash
   df -h
   docker system df
   ```

3. **限制容器资源**
   在 `docker-compose.yml` 中添加资源限制：
   ```yaml
   services:
     user-service:
       deploy:
         resources:
           limits:
             memory: 512M
   ```

---

## 停止服务

### 停止并保留数据

```bash
# 停止服务但保留数据卷
docker compose stop

# 或使用 Makefile
make stop
```

### 停止并删除数据

```bash
# ⚠️ 警告：这会删除所有数据！
docker compose down -v
```

### 完全清理

```bash
# 停止并删除所有容器、网络、数据卷
docker compose down -v --remove-orphans

# 清理未使用的 Docker 资源
docker system prune -a
```

---

## 下一步

- 📖 阅读 [TUTORIAL.md](./TUTORIAL.md) 了解架构设计和开发指南
- 🔧 查看 [API.md](./API.md) 了解完整的 API 接口文档（已整合到教程中）
- 🚀 开始开发你的第一个微服务功能

---

**Happy Coding! 🎉**
