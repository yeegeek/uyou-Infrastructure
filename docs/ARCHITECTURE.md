# 系统架构设计详解

本文档详细说明 uyou 社交系统的架构设计决策、技术选型和扩展规划。

## 目录

- [1. 架构演进](#1-架构演进)
- [2. 整体架构](#2-整体架构)
- [3. 微服务划分](#3-微服务划分)
- [4. 技术选型](#4-技术选型)
- [5. 数据流设计](#5-数据流设计)
- [6. 扩展性设计](#6-扩展性设计)
- [7. 高可用设计](#7-高可用设计)

---

## 1. 架构演进

### 1.1 单体应用 → 微服务

#### 单体应用的问题

```
┌────────────────────────────────┐
│      Monolithic Application     │
│  ┌──────────────────────────┐  │
│  │   User Module            │  │
│  │   Order Module           │  │
│  │   Feed Module            │  │
│  │   Message Module         │  │
│  └──────────────────────────┘  │
│             ↓                   │
│      Single Database            │
└────────────────────────────────┘
```

**问题**：
- **扩展困难**：无法单独扩展某个模块
- **部署风险**：一个模块出问题，整个应用都挂
- **技术栈固定**：所有模块必须用同一种语言
- **团队协作**：多个团队修改同一个代码库，容易冲突

#### 微服务架构的优势

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ User Service│  │Order Service│  │Feed Service │
│   Go + PG   │  │   Go + PG   │  │  Go + Mongo │
└─────────────┘  └─────────────┘  └─────────────┘
```

**优势**：
- **独立扩展**：Feed 服务流量大，只扩展 Feed 服务
- **技术自由**：可以为不同服务选择最合适的技术栈
- **故障隔离**：Order 服务挂了，User 服务仍然可用
- **团队自治**：每个团队负责自己的服务，独立开发部署

### 1.2 为什么需要 API Gateway

#### 没有网关的问题

```
Mobile App → User Service (REST)
           → Order Service (gRPC)
           → Feed Service (GraphQL)
```

客户端需要：
- 知道所有服务的地址
- 支持多种协议（REST、gRPC、GraphQL）
- 分别处理认证和错误

#### 使用网关后

```
Mobile App → API Gateway → User Service
                         → Order Service
                         → Feed Service
```

客户端只需要：
- 知道网关地址
- 使用统一的 REST API
- 网关处理认证、限流、协议转换

---

## 2. 整体架构

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────┐
│                     Client Layer                         │
│  Web App  │  Mobile App  │  Third-party API              │
└────────────────────┬────────────────────────────────────┘
                     │ REST/JSON
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  API Gateway Layer                       │
│                  Apache APISIX                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │  • REST to gRPC Transcoding                      │  │
│  │  • JWT Authentication                            │  │
│  │  • Rate Limiting & Circuit Breaking              │  │
│  │  │  • CORS & Security Headers                    │  │
│  │  • Request Logging & Tracing                     │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │ gRPC
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│User Service │ │Order Service│ │Feed Service │
│             │ │             │ │             │
│  Business   │ │  Business   │ │  Business   │
│   Logic     │ │   Logic     │ │   Logic     │
│             │ │             │ │             │
│ ┌─────────┐ │ │ ┌─────────┐ │ │ ┌─────────┐ │
│ │PostgreSQL│ │ │ │PostgreSQL│ │ │ │ MongoDB │ │
│ └─────────┘ │ │ └─────────┘ │ │ └─────────┘ │
│ ┌─────────┐ │ │ ┌─────────┐ │ │ ┌─────────┐ │
│ │  Redis  │ │ │ │  Redis  │ │ │ │  Redis  │ │
│ └─────────┘ │ │ └─────────┘ │ │ └─────────┘ │
└─────────────┘ └─────────────┘ └─────────────┘

┌─────────────────────────────────────────────────────────┐
│              Infrastructure Layer                        │
│  etcd  │  Prometheus  │  Jaeger  │  ELK Stack            │
└─────────────────────────────────────────────────────────┘
```

### 2.2 网络拓扑

```
Internet
    │
    ▼
[Load Balancer]  (Nginx / AWS ALB)
    │
    ▼
[APISIX Cluster]  (3 nodes)
    │
    ├─────────────────┬─────────────────┐
    │                 │                 │
    ▼                 ▼                 ▼
[User Service]  [Order Service]  [Feed Service]
 (3 instances)   (2 instances)    (5 instances)
    │                 │                 │
    ▼                 ▼                 ▼
[PostgreSQL]    [PostgreSQL]      [MongoDB]
 (Master-Slave)  (Master-Slave)    (Replica Set)
```

---

## 3. 微服务划分

### 3.1 划分原则

#### 按业务领域划分（DDD）
- **User Service**：用户域（注册、登录、个人资料）
- **Order Service**：交易域（订单、支付、退款）
- **Feed Service**：内容域（动态、评论、点赞）

#### 按数据特征划分
- **强一致性** → PostgreSQL（User、Order）
- **高吞吐量** → MongoDB（Feed）

#### 按扩展需求划分
- **Feed Service**：用户量大，读写频繁，需要独立扩展
- **Order Service**：交易高峰期需要独立扩展
- **User Service**：相对稳定，扩展需求较小

### 3.2 服务详细设计

#### User Service（用户服务）

**职责**：
- 用户注册、登录、认证
- 个人资料管理
- 用户关系（关注、粉丝）

**技术栈**：
- **语言**：Go 1.21+
- **数据库**：PostgreSQL 15
- **缓存**：Redis 7
- **端口**：50051 (gRPC)

**数据库设计**：
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,  -- bcrypt hash
    avatar VARCHAR(255),
    bio TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);

CREATE TABLE user_follows (
    id SERIAL PRIMARY KEY,
    follower_id INT NOT NULL,
    following_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(follower_id, following_id),
    FOREIGN KEY (follower_id) REFERENCES users(id),
    FOREIGN KEY (following_id) REFERENCES users(id)
);
```

**缓存策略**：
- 用户信息：`user:{id}` → TTL 24小时
- 用户关注列表：`user:{id}:following` → TTL 1小时

#### Order Service（订单服务）

**职责**：
- 订单创建、查询、取消
- 支付流程管理
- 订单状态跟踪

**技术栈**：
- **语言**：Go 1.21+
- **数据库**：PostgreSQL 15
- **缓存**：Redis 7
- **端口**：50052 (gRPC)

**数据库设计**：
```sql
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    order_no VARCHAR(50) UNIQUE NOT NULL,
    user_id INT NOT NULL,
    total_amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) NOT NULL,  -- pending, paid, shipped, completed, cancelled
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    quantity INT NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);
```

**事务处理**：
```go
func (s *server) CreateOrder(ctx context.Context, req *pb.CreateOrderRequest) (*pb.CreateOrderResponse, error) {
    // 开始事务
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return nil, err
    }
    defer tx.Rollback()
    
    // 1. 创建订单
    var orderID int64
    err = tx.QueryRow("INSERT INTO orders (...) VALUES (...) RETURNING id").Scan(&orderID)
    
    // 2. 创建订单项
    for _, item := range req.Items {
        _, err = tx.Exec("INSERT INTO order_items (...) VALUES (...)")
    }
    
    // 3. 提交事务
    if err := tx.Commit(); err != nil {
        return nil, err
    }
    
    return &pb.CreateOrderResponse{OrderId: orderID}, nil
}
```

#### Feed Service（动态服务）

**职责**：
- 动态发布、删除
- 时间线生成
- 点赞、评论

**技术栈**：
- **语言**：Go 1.21+
- **数据库**：MongoDB 7
- **缓存**：Redis 7
- **端口**：50053 (gRPC)

**数据模型**：
```javascript
// feeds 集合
{
  "_id": ObjectId("..."),
  "user_id": 123,
  "content": "今天天气真好！",
  "images": ["https://cdn.example.com/img1.jpg"],
  "location": {
    "name": "北京",
    "lat": 39.9042,
    "lng": 116.4074
  },
  "likes": 10,
  "comments": 5,
  "created_at": ISODate("2026-01-22T10:30:00Z"),
  "updated_at": ISODate("2026-01-22T10:30:00Z")
}

// 索引
db.feeds.createIndex({ "user_id": 1, "created_at": -1 })
db.feeds.createIndex({ "created_at": -1 })
```

**时间线算法**：
```go
// 拉模式（Pull）：用户请求时实时生成
func (s *server) GetTimeline(ctx context.Context, req *pb.GetTimelineRequest) (*pb.GetTimelineResponse, error) {
    // 1. 获取用户关注列表
    followingIDs := s.getFollowingIDs(req.UserId)
    
    // 2. 查询关注用户的动态
    filter := bson.M{
        "user_id": bson.M{"$in": followingIDs},
        "created_at": bson.M{"$lt": req.LastTimestamp},
    }
    
    cursor, err := s.mongodb.Find(ctx, filter, options.Find().
        SetSort(bson.D{{Key: "created_at", Value: -1}}).
        SetLimit(20))
    
    // 3. 返回结果
    var feeds []*pb.Feed
    cursor.All(ctx, &feeds)
    return &pb.GetTimelineResponse{Feeds: feeds}, nil
}
```

---

## 4. 技术选型

### 4.1 API Gateway：Apache APISIX

#### 为什么选择 APISIX

| 特性 | APISIX | Kong | Traefik |
|------|--------|------|---------|
| 性能 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| 动态配置 | ✅ etcd | ✅ PostgreSQL | ❌ 文件 |
| REST to gRPC | ✅ 内置 | ❌ 需插件 | ❌ 不支持 |
| 插件生态 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| 学习曲线 | 中等 | 中等 | 简单 |

**选择理由**：
1. **高性能**：基于 Nginx + LuaJIT，单实例可达 10万+ QPS
2. **动态配置**：使用 etcd，配置修改无需重启
3. **REST to gRPC**：内置支持，无需额外开发
4. **活跃社区**：Apache 顶级项目，更新频繁

### 4.2 RPC 框架：gRPC

#### 为什么选择 gRPC

| 特性 | gRPC | REST | Thrift |
|------|------|------|--------|
| 性能 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| 跨语言 | ✅ | ✅ | ✅ |
| 流式传输 | ✅ | ❌ | 有限 |
| 浏览器支持 | ❌ | ✅ | ❌ |
| 学习成本 | 中等 | 低 | 高 |

**选择理由**：
1. **性能优异**：HTTP/2 + Protobuf，比 REST/JSON 快 5-10 倍
2. **强类型**：编译时检查，减少运行时错误
3. **流式传输**：支持双向流，适合实时通信
4. **生态成熟**：Google 维护，社区活跃

### 4.3 配置中心：etcd

#### 为什么选择 etcd

| 特性 | etcd | Consul | ZooKeeper |
|------|------|--------|-----------|
| 一致性 | Raft | Raft | ZAB |
| 性能 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| Watch 机制 | ✅ | ✅ | ✅ |
| HTTP API | ✅ | ✅ | ❌ |
| APISIX 集成 | ✅ 原生 | ✅ 插件 | ❌ |

**选择理由**：
1. **APISIX 原生支持**：无需额外配置
2. **简单易用**：HTTP API，易于调试
3. **高可用**：Raft 算法保证一致性
4. **轻量级**：资源占用少

### 4.4 数据库选型

#### PostgreSQL vs MongoDB

| 场景 | PostgreSQL | MongoDB |
|------|-----------|---------|
| 用户数据 | ✅ 强一致性 | ❌ |
| 订单数据 | ✅ ACID 事务 | ❌ |
| 动态内容 | ❌ Schema 固定 | ✅ 灵活 |
| 高吞吐 | ❌ 垂直扩展 | ✅ 水平扩展 |

**选择理由**：
- **PostgreSQL**：用户和订单需要强一致性和事务支持
- **MongoDB**：动态内容 Schema 灵活，读写量大，易于扩展

---

## 5. 数据流设计

### 5.1 用户注册流程

```
1. 客户端发起注册请求
   POST /api/v1/users/register
   {"username": "alice", "email": "alice@example.com", "password": "pass123"}

2. APISIX 接收请求
   - 检查限流：100 次/分钟
   - 转码：JSON → Protobuf
   - 路由：user-service:50051

3. User Service 处理
   - 验证数据：用户名长度、邮箱格式
   - 检查重复：查询数据库
   - 加密密码：bcrypt.GenerateFromPassword()
   - 写入数据库：INSERT INTO users
   - 返回响应：RegisterResponse{user_id: 5}

4. APISIX 返回客户端
   - 转码：Protobuf → JSON
   - 返回：{"user_id": 5, "message": "success"}
```

### 5.2 订单创建流程

```
1. 客户端发起创建订单请求
   POST /api/v1/orders
   {"user_id": 1, "items": [...], "total_amount": 199.98}

2. Order Service 处理（事务）
   BEGIN TRANSACTION
   
   - 创建订单记录
     INSERT INTO orders (order_no, user_id, total_amount, status)
     VALUES ('ORD20260122001', 1, 199.98, 'pending')
   
   - 创建订单项
     INSERT INTO order_items (order_id, product_id, quantity, price)
     VALUES (1, 1001, 2, 99.99)
   
   - 调用库存服务（未来扩展）
     grpc.Call(inventory-service, "DecreaseStock", ...)
   
   COMMIT TRANSACTION

3. 缓存订单信息
   redis.Set("order:1", orderData, 1*time.Hour)

4. 返回响应
   {"order_id": 1, "order_no": "ORD20260122001"}
```

### 5.3 动态时间线流程

```
1. 客户端请求时间线
   GET /api/v1/feeds/timeline?page=1&limit=20

2. Feed Service 处理
   - 获取用户关注列表
     followingIDs := redis.Get("user:1:following")
     if followingIDs == nil {
         followingIDs = db.Query("SELECT following_id FROM user_follows WHERE follower_id = 1")
         redis.Set("user:1:following", followingIDs, 1*time.Hour)
     }
   
   - 查询关注用户的动态
     feeds := mongodb.Find({
         user_id: {$in: followingIDs},
         created_at: {$lt: lastTimestamp}
     }).Sort({created_at: -1}).Limit(20)
   
   - 返回结果
     {"feeds": [...], "has_more": true}
```

---

## 6. 扩展性设计

### 6.1 水平扩展

#### 无状态服务
所有微服务都是无状态的，可以随意增加实例。

```bash
# 扩展 Feed Service 到 5 个实例
docker-compose up -d --scale feed-service=5
```

APISIX 自动负载均衡到所有实例。

#### 数据库分片

**User Service - 按用户ID分片**：
```
user_id % 4 = 0 → DB Shard 0
user_id % 4 = 1 → DB Shard 1
user_id % 4 = 2 → DB Shard 2
user_id % 4 = 3 → DB Shard 3
```

**Feed Service - 按时间分片**：
```
2026-01 → MongoDB Cluster 1
2026-02 → MongoDB Cluster 2
2026-03 → MongoDB Cluster 3
```

### 6.2 缓存扩展

#### Redis Cluster
使用 Redis Cluster 实现水平扩展。

```
Redis Cluster:
├── Master 1 (Slots 0-5460)
├── Master 2 (Slots 5461-10922)
└── Master 3 (Slots 10923-16383)
```

#### 多级缓存
```
L1: 本地缓存 (Go map + sync.RWMutex)
    ↓ Miss
L2: Redis
    ↓ Miss
L3: 数据库
```

### 6.3 消息队列

引入消息队列解耦服务，提高吞吐量。

```
Order Service → [RabbitMQ] → Email Service (发送订单确认邮件)
                           → Inventory Service (扣减库存)
                           → Analytics Service (统计分析)
```

---

## 7. 高可用设计

### 7.1 服务高可用

#### 多实例部署
每个服务至少 2 个实例，避免单点故障。

```
User Service: 3 instances
Order Service: 2 instances
Feed Service: 5 instances
```

#### 健康检查
```go
func (s *server) HealthCheck(ctx context.Context, req *pb.HealthCheckRequest) (*pb.HealthCheckResponse, error) {
    // 检查数据库连接
    if err := s.db.Ping(); err != nil {
        return &pb.HealthCheckResponse{Status: "unhealthy"}, nil
    }
    
    // 检查 Redis 连接
    if err := s.redis.Ping(ctx).Err(); err != nil {
        return &pb.HealthCheckResponse{Status: "unhealthy"}, nil
    }
    
    return &pb.HealthCheckResponse{Status: "healthy"}, nil
}
```

#### 自动重启
```yaml
# docker-compose.yml
services:
  user-service:
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "grpc_health_probe", "-addr=:50051"]
      interval: 10s
      timeout: 5s
      retries: 3
```

### 7.2 数据库高可用

#### PostgreSQL 主从复制
```
Master (Write) ← Replication ← Slave 1 (Read)
                              ← Slave 2 (Read)
```

#### MongoDB 副本集
```
Primary ← Replication ← Secondary 1
                      ← Secondary 2
```

自动故障转移：Primary 挂了，Secondary 自动升级为 Primary。

### 7.3 熔断和降级

#### 熔断器
```yaml
# APISIX 配置
plugins:
  api-breaker:
    break_response_code: 503
    max_breaker_sec: 300
    unhealthy:
      http_statuses: [500, 503]
      failures: 3
    healthy:
      http_statuses: [200]
      successes: 3
```

#### 服务降级
```go
func (s *server) GetTimeline(ctx context.Context, req *pb.GetTimelineRequest) (*pb.GetTimelineResponse, error) {
    // 尝试从缓存获取
    cached, err := s.redis.Get(ctx, cacheKey).Result()
    if err == nil {
        return parseCachedTimeline(cached), nil
    }
    
    // 尝试从数据库获取
    feeds, err := s.mongodb.Find(ctx, filter)
    if err != nil {
        // 降级：返回空列表，而不是报错
        log.Warn("Failed to get timeline, returning empty list")
        return &pb.GetTimelineResponse{Feeds: []*pb.Feed{}}, nil
    }
    
    return &pb.GetTimelineResponse{Feeds: feeds}, nil
}
```

---

## 总结

本文档详细说明了 uyou 社交系统的架构设计：

1. **架构演进**：从单体应用到微服务，引入 API Gateway
2. **整体架构**：四层架构（客户端、网关、微服务、基础设施）
3. **微服务划分**：按业务领域、数据特征、扩展需求划分
4. **技术选型**：APISIX、gRPC、etcd、PostgreSQL、MongoDB
5. **数据流设计**：用户注册、订单创建、动态时间线
6. **扩展性设计**：水平扩展、数据库分片、消息队列
7. **高可用设计**：多实例、主从复制、熔断降级

这个架构设计支持 **10万+ 并发用户**，并且可以通过水平扩展支持更大规模。

**下一步**：阅读 [MICROSERVICE-PATTERNS.md](./MICROSERVICE-PATTERNS.md) 学习微服务设计模式。
