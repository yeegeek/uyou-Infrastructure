# 核心概念详解

本文档深入讲解 uyou 微服务架构中的核心技术概念，帮助您理解系统的工作原理。

## 目录

- [1. API Gateway（API 网关）](#1-api-gatewayapi-网关)
- [2. gRPC 和 Protocol Buffers](#2-grpc-和-protocol-buffers)
- [3. REST to gRPC 转码](#3-rest-to-grpc-转码)
- [4. etcd 配置中心](#4-etcd-配置中心)
- [5. 服务发现和负载均衡](#5-服务发现和负载均衡)
- [6. 微服务通信模式](#6-微服务通信模式)
- [7. 缓存策略](#7-缓存策略)
- [8. 数据库选型](#8-数据库选型)

---

## 1. API Gateway（API 网关）

### 1.1 什么是 API Gateway

**API Gateway** 是微服务架构中的统一入口，所有客户端请求都先到达网关，再由网关路由到后端微服务。它就像一个"交通枢纽"，负责请求的分发、协议转换、安全认证等工作。

### 1.2 为什么需要 API Gateway

在微服务架构中，如果没有网关，客户端需要直接调用多个微服务：

```
客户端 → User Service (http://user:8001)
客户端 → Order Service (http://order:8002)
客户端 → Feed Service (http://feed:8003)
```

这种方式存在以下问题：

**问题 1：客户端复杂度高**
- 客户端需要知道所有微服务的地址
- 需要处理不同服务的认证方式
- 需要管理多个连接

**问题 2：安全风险**
- 微服务直接暴露给外网
- 难以统一实施安全策略
- 无法集中管理访问控制

**问题 3：协议不统一**
- 有的服务用 REST，有的用 gRPC
- 客户端需要支持多种协议
- 增加开发和维护成本

使用 API Gateway 后：

```
客户端 → API Gateway → User Service
                    → Order Service
                    → Feed Service
```

**优势**：
- **统一入口**：客户端只需要知道网关地址
- **协议转换**：网关将 REST 转为 gRPC，客户端无需关心
- **安全集中**：在网关层统一处理认证、授权、限流
- **服务解耦**：后端服务变更不影响客户端

### 1.3 Apache APISIX 特性

我们选择 **Apache APISIX** 作为 API Gateway，它提供以下核心功能：

#### 动态路由
路由配置存储在 etcd 中，修改后立即生效，无需重启服务。

```yaml
routes:
  - uri: /api/v1/users/register
    upstream:
      nodes:
        "user-service:50051": 1
      scheme: grpc
```

#### 协议转码
自动将客户端的 REST/JSON 请求转换为后端的 gRPC 调用。

```
REST: POST /api/v1/users/register {"username": "alice"}
  ↓
gRPC: user.UserService/Register(RegisterRequest{username: "alice"})
```

#### 插件系统
通过插件扩展功能，无需修改核心代码。

```yaml
plugins:
  jwt-auth:           # JWT 认证
    key: user-key
  limit-count:        # 限流
    count: 100
    time_window: 60
  cors:               # 跨域
    allow_origins: "*"
```

#### 高性能
基于 Nginx + LuaJIT，单实例可处理数万 QPS。

---

## 2. gRPC 和 Protocol Buffers

### 2.1 什么是 gRPC

**gRPC** 是 Google 开发的高性能 RPC（Remote Procedure Call）框架。它允许你像调用本地函数一样调用远程服务。

**传统 HTTP REST 调用**：
```go
// 客户端需要手动构造 HTTP 请求
resp, err := http.Post("http://user-service/register", 
    "application/json",
    bytes.NewBuffer(jsonData))
// 手动解析响应
var result RegisterResponse
json.Unmarshal(resp.Body, &result)
```

**gRPC 调用**：
```go
// 像调用本地函数一样简单
client := pb.NewUserServiceClient(conn)
resp, err := client.Register(ctx, &pb.RegisterRequest{
    Username: "alice",
    Email: "alice@example.com",
})
```

### 2.2 gRPC 的优势

#### 性能优异
- **HTTP/2**：多路复用、头部压缩、服务端推送
- **Protobuf**：二进制序列化，比 JSON 小 3-10 倍
- **连接复用**：一个连接可以同时处理多个请求

**性能对比**：
| 指标 | REST/JSON | gRPC/Protobuf |
|------|-----------|---------------|
| 序列化大小 | 100 KB | 30 KB |
| 序列化速度 | 1x | 5-10x |
| 网络传输 | 慢 | 快 |

#### 强类型接口
通过 Proto 文件定义接口，编译时检查类型错误。

```protobuf
service UserService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
}

message RegisterRequest {
  string username = 1;  // 必须是字符串
  string email = 2;     // 必须是字符串
}
```

如果传错类型，编译时就会报错，而不是运行时才发现。

#### 自动生成代码
从 Proto 文件自动生成客户端和服务端代码，减少手写代码量。

```bash
protoc --go_out=. --go-grpc_out=. user.proto
# 生成 user.pb.go 和 user_grpc.pb.go
```

### 2.3 Protocol Buffers 详解

**Protocol Buffers（Protobuf）** 是 Google 的数据序列化格式，类似于 JSON 和 XML，但更小更快。

#### 基本语法

```protobuf
syntax = "proto3";  // 使用 proto3 语法

package user;  // 包名

// 消息定义（类似于 struct）
message User {
  int64 id = 1;           // 字段编号，不是默认值
  string username = 2;
  string email = 3;
  bool is_active = 4;
  repeated string tags = 5;  // 数组类型
}
```

#### 字段编号的重要性

**字段编号** 是 Protobuf 的核心概念，它用于标识字段，而不是字段名。

```protobuf
message User {
  string username = 1;  // 编号 1
  string email = 2;     // 编号 2
}
```

序列化后的数据：
```
[1: "alice", 2: "alice@example.com"]
```

**注意**：字段编号一旦使用就不能改变，否则会导致数据不兼容。

#### 数据类型映射

| Proto 类型 | Go 类型 | 说明 |
|-----------|---------|------|
| int32, int64 | int32, int64 | 整数 |
| uint32, uint64 | uint32, uint64 | 无符号整数 |
| float, double | float32, float64 | 浮点数 |
| bool | bool | 布尔值 |
| string | string | UTF-8 字符串 |
| bytes | []byte | 字节数组 |
| repeated T | []T | 数组/切片 |

#### repeated 关键字（数组）

```protobuf
message CreateFeedRequest {
  int64 user_id = 1;
  repeated string images = 2;  // 图片数组
  repeated int64 mentioned_users = 3;  // 提到的用户ID数组
}
```

对应的 Go 代码：
```go
req := &pb.CreateFeedRequest{
    UserId: 1,
    Images: []string{"img1.jpg", "img2.jpg"},
    MentionedUsers: []int64{2, 3, 4},
}
```

JSON 表示：
```json
{
  "user_id": 1,
  "images": ["img1.jpg", "img2.jpg"],
  "mentioned_users": [2, 3, 4]
}
```

---

## 3. REST to gRPC 转码

### 3.1 转码原理

**REST to gRPC 转码** 是 APISIX 的核心功能，它允许客户端使用熟悉的 REST API，而后端使用高性能的 gRPC。

#### 转码流程

```
1. 客户端发送 REST 请求
   POST /api/v1/users/register
   Content-Type: application/json
   {"username": "alice", "email": "alice@example.com"}

2. APISIX 接收请求
   - 匹配路由：/api/v1/users/register
   - 找到 grpc-transcode 插件配置

3. 读取 Proto 定义
   - 从 etcd 读取 proto_id: "1"
   - 解析 Proto 文件，找到 RegisterRequest 定义

4. JSON to Protobuf 转换
   - 根据 Proto 定义解析 JSON
   - 构建 RegisterRequest 对象
   - 序列化为 Protobuf 二进制

5. 发起 gRPC 调用
   - 连接 user-service:50051
   - 调用 user.UserService/Register
   - 传递 Protobuf 数据

6. 接收 gRPC 响应
   - 微服务返回 RegisterResponse
   - Protobuf 二进制数据

7. Protobuf to JSON 转换
   - 反序列化 Protobuf
   - 根据 Proto 定义转换为 JSON

8. 返回客户端
   HTTP 200 OK
   Content-Type: application/json
   {"user_id": 5, "message": "success"}
```

### 3.2 配置示例

```yaml
routes:
  - uri: /api/v1/users/register
    methods: [POST]
    upstream:
      type: roundrobin
      nodes:
        "user-service:50051": 1
      scheme: grpc  # 指定使用 gRPC 协议
    plugins:
      grpc-transcode:
        proto_id: "1"  # Proto 定义的 ID
        service: user.UserService  # gRPC 服务名
        method: Register  # gRPC 方法名
```

### 3.3 Proto 定义的两种用途

#### 用途 1：编译时代码生成

在微服务开发时，使用 `protoc` 编译器生成 Go 代码：

```bash
protoc --go_out=. --go-grpc_out=. proto/user.proto
```

生成的文件：
- `user.pb.go`：消息类型定义
- `user_grpc.pb.go`：gRPC 服务接口

微服务使用生成的代码：
```go
import pb "github.com/uyou/user-service/proto"

func (s *server) Register(ctx context.Context, req *pb.RegisterRequest) (*pb.RegisterResponse, error) {
    // 实现逻辑
}
```

#### 用途 2：运行时转码

在 APISIX 运行时，Proto 定义用于 REST 和 gRPC 之间的转换：

```yaml
proto:
  - id: "1"
    content: |
      syntax = "proto3";
      package user;
      service UserService {
        rpc Register(RegisterRequest) returns (RegisterResponse);
      }
      message RegisterRequest {
        string username = 1;
        string email = 2;
      }
      message RegisterResponse {
        int64 user_id = 1;
        string message = 2;
      }
```

APISIX 读取这个定义，知道如何将 JSON 转换为 Protobuf。

---

## 4. etcd 配置中心

### 4.1 什么是 etcd

**etcd** 是一个分布式键值存储系统，主要用于配置管理和服务发现。它类似于 Redis，但专为分布式系统设计。

### 4.2 etcd 的特性

#### 强一致性
使用 Raft 算法保证数据一致性，所有节点的数据始终相同。

#### Watch 机制
客户端可以监听某个 key 的变化，当数据更新时立即收到通知。

```go
watcher := client.Watch(ctx, "/apisix/routes/")
for resp := range watcher {
    for _, ev := range resp.Events {
        fmt.Printf("Key: %s, Value: %s\n", ev.Kv.Key, ev.Kv.Value)
    }
}
```

APISIX 正是利用这个机制实现动态配置更新。

#### 租约（Lease）
可以为 key 设置过期时间，实现服务注册和心跳检测。

### 4.3 APISIX 如何使用 etcd

#### 配置存储结构

```
/apisix/
├── routes/           # 路由配置
│   ├── 1            # 路由 ID 1
│   ├── 2            # 路由 ID 2
│   └── 3            # 路由 ID 3
├── protos/          # Proto 定义
│   ├── 1            # Proto ID 1
│   └── 2            # Proto ID 2
├── upstreams/       # 上游服务
│   └── 1            # 上游 ID 1
└── services/        # 服务定义
    └── 1            # 服务 ID 1
```

#### 配置更新流程

```
1. 管理员修改路由配置
   vim apisix/config/routes/user-routes.yaml

2. 运行部署脚本
   make update-apisix-merge

3. 脚本调用 APISIX Admin API
   curl -X PUT http://localhost:9180/apisix/admin/routes/1 \
     -H "X-API-KEY: xxx" \
     -d @route-config.json

4. APISIX Admin API 写入 etcd
   etcdctl put /apisix/routes/1 '{"uri": "/api/v1/users/register", ...}'

5. APISIX 监听到 etcd 变化
   watcher 收到通知：/apisix/routes/1 已更新

6. APISIX 重新加载配置
   读取新的路由配置，应用到 Nginx

7. 配置生效
   新的请求使用新配置路由
```

### 4.4 查看 etcd 数据

```bash
# 查看所有路由
docker exec -it uyou-etcd etcdctl get /apisix/routes/ --prefix

# 查看特定路由
docker exec -it uyou-etcd etcdctl get /apisix/routes/1

# 查看所有 Proto
docker exec -it uyou-etcd etcdctl get /apisix/protos/ --prefix
```

---

## 5. 服务发现和负载均衡

### 5.1 服务发现

在微服务架构中，服务实例的地址可能动态变化（扩容、缩容、故障重启），**服务发现** 机制负责维护服务实例列表。

#### 静态配置（当前方案）

```yaml
upstream:
  type: roundrobin
  nodes:
    "user-service:50051": 1  # 固定地址
```

优点：简单，适合开发环境
缺点：无法动态扩展

#### 动态服务发现（生产环境）

```yaml
upstream:
  type: roundrobin
  discovery_type: "consul"  # 使用 Consul 服务发现
  service_name: "user-service"
```

APISIX 自动从 Consul 获取 user-service 的所有实例地址。

### 5.2 负载均衡算法

#### Round Robin（轮询）
依次将请求分配给每个实例。

```
请求1 → 实例A
请求2 → 实例B
请求3 → 实例C
请求4 → 实例A  # 循环
```

#### Consistent Hash（一致性哈希）
根据请求的某个字段（如 user_id）计算哈希，相同的请求总是路由到同一个实例。

```yaml
upstream:
  type: chash
  hash_on: "vars"
  key: "arg_user_id"  # 根据 user_id 参数哈希
```

适用场景：需要会话保持或本地缓存的场景。

#### Weighted Round Robin（加权轮询）
根据实例的权重分配请求。

```yaml
upstream:
  type: roundrobin
  nodes:
    "user-service-1:50051": 3  # 权重 3
    "user-service-2:50051": 1  # 权重 1
```

实例1 会收到 75% 的请求，实例2 收到 25%。

---

## 6. 微服务通信模式

### 6.1 同步调用（Request-Response）

客户端发送请求，等待响应。

```
Client → Service A → Service B
       ← Response  ← Response
```

**优点**：简单直观，易于理解和调试
**缺点**：耦合度高，响应时间累加

### 6.2 异步消息（Message Queue）

通过消息队列解耦服务。

```
Service A → [Message Queue] → Service B
```

**优点**：解耦，削峰填谷
**缺点**：复杂度高，需要处理消息丢失和重复

### 6.3 事件驱动（Event-Driven）

服务发布事件，其他服务订阅感兴趣的事件。

```
Order Service → [Event Bus] → Email Service
                            → Inventory Service
                            → Analytics Service
```

**优点**：高度解耦，易于扩展
**缺点**：难以追踪调用链，调试困难

---

## 7. 缓存策略

### 7.1 Cache-Aside 模式

这是最常用的缓存模式，也是我们项目采用的方案。

#### 读取流程

```
1. 客户端请求数据
2. 检查缓存
   - 缓存命中 → 返回缓存数据
   - 缓存未命中 → 继续
3. 从数据库读取
4. 写入缓存
5. 返回数据
```

代码示例：
```go
func (s *server) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.GetUserResponse, error) {
    cacheKey := fmt.Sprintf("user:%d", req.UserId)
    
    // 1. 尝试从缓存读取
    cached, err := s.redis.Get(ctx, cacheKey).Result()
    if err == nil {
        // 缓存命中
        var user User
        json.Unmarshal([]byte(cached), &user)
        return &user, nil
    }
    
    // 2. 缓存未命中，从数据库读取
    var user User
    err = s.db.QueryRow("SELECT * FROM users WHERE id = $1", req.UserId).Scan(&user)
    
    // 3. 写入缓存
    userData, _ := json.Marshal(user)
    s.redis.Set(ctx, cacheKey, userData, time.Hour*24)
    
    return &user, nil
}
```

#### 更新流程

```
1. 更新数据库
2. 删除缓存（而不是更新缓存）
```

为什么删除而不是更新？
- 避免并发更新导致的数据不一致
- 如果数据很少被读取，更新缓存是浪费

### 7.2 缓存失效策略

#### TTL（Time To Live）
设置过期时间，到期自动删除。

```go
s.redis.Set(ctx, key, value, time.Hour*24)  // 24小时过期
```

#### LRU（Least Recently Used）
Redis 默认策略，内存不足时删除最少使用的数据。

```
redis.conf:
maxmemory-policy allkeys-lru
```

### 7.3 缓存穿透和雪崩

#### 缓存穿透
查询不存在的数据，缓存和数据库都没有，导致每次都查询数据库。

**解决方案**：布隆过滤器
```go
// 先检查布隆过滤器
if !bloomFilter.Exists(userId) {
    return nil, errors.New("user not found")
}
```

#### 缓存雪崩
大量缓存同时过期，导致数据库压力骤增。

**解决方案**：随机过期时间
```go
ttl := time.Hour*24 + time.Duration(rand.Intn(3600))*time.Second
s.redis.Set(ctx, key, value, ttl)
```

---

## 8. 数据库选型

### 8.1 PostgreSQL vs MongoDB

| 特性 | PostgreSQL | MongoDB |
|------|-----------|---------|
| 数据模型 | 关系型（表） | 文档型（JSON） |
| 事务支持 | ACID | 有限支持 |
| 查询语言 | SQL | MongoDB Query Language |
| 扩展性 | 垂直扩展为主 | 水平扩展友好 |
| 适用场景 | 强一致性、复杂查询 | 高吞吐、灵活 Schema |

### 8.2 我们的选择

#### User Service → PostgreSQL
- 用户数据需要强一致性
- 需要唯一性约束（用户名、邮箱）
- 查询相对简单

#### Order Service → PostgreSQL
- 订单涉及金额，必须保证 ACID
- 需要事务支持（订单+订单项）
- 需要复杂的统计查询

#### Feed Service → MongoDB
- 动态内容读写量大
- Schema 灵活（图片、视频、位置等）
- 不需要复杂的关联查询
- 水平扩展友好

### 8.3 数据库连接池

使用连接池复用数据库连接，提高性能。

```go
db, err := sql.Open("postgres", connStr)
db.SetMaxOpenConns(25)  // 最大连接数
db.SetMaxIdleConns(5)   // 最大空闲连接数
db.SetConnMaxLifetime(5 * time.Minute)  // 连接最大生命周期
```

---

## 总结

本文档详细讲解了 uyou 微服务架构的核心概念：

1. **API Gateway**：统一入口，协议转换，安全集中
2. **gRPC**：高性能 RPC 框架，强类型接口
3. **Protocol Buffers**：高效的数据序列化格式
4. **REST to gRPC 转码**：客户端用 REST，后端用 gRPC
5. **etcd**：配置中心，动态配置更新
6. **服务发现**：维护服务实例列表
7. **缓存策略**：Cache-Aside 模式，提高性能
8. **数据库选型**：根据业务特点选择合适的数据库

理解这些概念后，您将能够更好地开发和维护微服务系统。

**下一步**：阅读 [DEVELOPMENT-GUIDE.md](./DEVELOPMENT-GUIDE.md) 开始实践开发。
