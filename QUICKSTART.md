# 快速开始指南

## 5 分钟快速体验微服务架构

### 步骤 1: 启动服务 (2分钟)

```bash
# 克隆仓库
git clone https://github.com/yeegeek/uyou-Infrastructure.git
cd uyou-Infrastructure

# 启动所有服务
docker-compose up -d

# 等待服务启动完成（约 1-2 分钟）
docker-compose ps
```

### 步骤 2: 测试用户服务 (1分钟)

```bash
# 注册新用户
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "email": "demo@example.com",
    "password": "demo123"
  }'

# 用户登录
curl -X POST http://localhost:9080/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "password": "demo123"
  }'
```

### 步骤 3: 测试订单服务 (1分钟)

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

### 步骤 4: 测试动态服务 (1分钟)

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

## 🎉 完成！

您已经成功体验了：
- ✅ REST API 通过 APISIX 网关访问
- ✅ APISIX 自动转码 REST 到 gRPC
- ✅ 三个微服务独立运行
- ✅ PostgreSQL 和 MongoDB 数据存储
- ✅ Redis 缓存加速

## 下一步

1. 查看 [README.md](./README.md) 了解完整功能
2. 阅读 [ARCHITECTURE.md](./ARCHITECTURE.md) 理解架构设计
3. 运行 `./scripts/test-api.sh` 执行完整测试
4. 访问 http://localhost:9000 查看 APISIX Dashboard

## 停止服务

```bash
docker-compose down
```

## 常见问题

**Q: 服务启动失败？**
A: 检查端口是否被占用，确保 9080、50051-50053 端口可用

**Q: API 返回 502 错误？**
A: 等待服务完全启动，运行 `docker-compose ps` 确认所有服务状态为 healthy

**Q: 如何查看日志？**
A: 运行 `docker-compose logs -f` 查看所有服务日志
