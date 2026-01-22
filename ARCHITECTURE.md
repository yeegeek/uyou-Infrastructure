# 社交系统微服务架构设计

## 架构概览

本项目采用 **API Gateway + 微服务** 架构模式，使用 Apache APISIX 作为统一网关，后端微服务使用 Go 语言开发，通过 gRPC 进行服务间通信。

### 核心组件

```
┌─────────────┐
│   客户端     │ (REST/JSON)
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────┐
│            Apache APISIX Gateway                    │
│  - JWT 认证                                          │
│  - 限流/熔断                                         │
│  - CORS                                             │
│  - 日志/TraceID                                      │
│  - REST → gRPC 转码                                  │
└──────┬──────────────────┬───────────────────┬──────┘
       │                  │                   │
       ▼                  ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   用户服务   │    │   交易服务   │    │   动态服务   │
│ (User)      │    │ (Order)     │    │ (Feed)      │
│             │    │             │    │             │
│ PostgreSQL  │    │ PostgreSQL  │    │ MongoDB     │
│ Redis       │    │ Redis       │    │ Redis       │
└─────────────┘    └─────────────┘    └─────────────┘
```

## 微服务划分

### 1. User Service (用户服务)
- **职责**: 用户注册、登录、认证、个人资料管理
- **技术栈**: Go + PostgreSQL + Redis
- **端口**: 50051 (gRPC)

### 2. Order Service (交易服务)
- **职责**: 商城订单、交易处理、支付流程
- **技术栈**: Go + PostgreSQL + Redis
- **端口**: 50052 (gRPC)

### 3. Feed Service (动态服务)
- **职责**: 用户动态、内容发布、时间线
- **技术栈**: Go + MongoDB + Redis
- **端口**: 50053 (gRPC)

## 技术选型

### API Gateway
- **Apache APISIX**: 高性能、云原生 API 网关
  - 支持 REST to gRPC 转码
  - 内置限流、熔断、认证插件
  - 动态路由配置

### 服务间通信
- **gRPC**: 高性能 RPC 框架
  - Protocol Buffers 序列化
  - HTTP/2 传输
  - 双向流支持

### 数据存储
- **PostgreSQL**: 关系型数据库，用于交易、用户等强一致性场景
- **MongoDB**: 文档数据库，用于动态、消息等高吞吐场景
- **Redis**: 缓存层，用于会话、热点数据

### 基础设施
- **Docker**: 容器化部署
- **Docker Compose**: 本地开发编排
- **etcd**: APISIX 配置中心

## 数据流

### 1. 客户端请求流程
```
Client → APISIX → gRPC Service → Database → Cache
  ↑                                              │
  └──────────────────────────────────────────────┘
```

### 2. JWT 认证流程
```
1. 客户端登录 → User Service → 生成 JWT Token
2. 后续请求携带 Token → APISIX 验证 → 转发到后端服务
3. 服务从 Header 获取用户信息 (APISIX 注入)
```

### 3. 服务间调用
```
Order Service → gRPC → User Service (查询用户信息)
              → gRPC → Feed Service (创建动态)
```

## 扩展性设计

### 水平扩展
- 所有微服务无状态设计，支持多实例部署
- APISIX 自动负载均衡
- 数据库读写分离、分片

### 高可用
- 服务多副本部署
- 健康检查和自动重启
- 熔断降级机制

### 监控观测
- TraceID 全链路追踪
- 统一日志收集
- 性能指标监控

## 目录结构

```
uyou-Infrastructure/
├── services/
│   ├── user/           # 用户服务
│   ├── order/          # 交易服务
│   └── feed/           # 动态服务
├── proto/              # gRPC 定义
├── apisix/             # APISIX 配置
├── docker-compose.yml  # Docker 编排
└── README.md           # 使用文档
```

## 部署方式

### 开发环境
```bash
docker compose up -d
```

### 生产环境
- Kubernetes 部署
- Helm Charts 管理
- CI/CD 自动化流水线
```
