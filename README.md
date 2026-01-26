# uyou-Infrastructure | API Gateway & 微服务框架

**高性能 API Gateway 基础设施** - 基于 Apache APISIX + Go + gRPC 的微服务架构学习与实践框架。

---

## 🚀 5 分钟快速开始

### 1. 启动环境
```bash
# 克隆并进入项目
git clone https://github.com/yeegeek/uyou-Infrastructure.git
cd uyou-Infrastructure

# 启动 Docker Compose
docker compose up -d
```

### 2. 部署路由配置
等待 1-2 分钟服务启动后，运行：
```bash
make update-apisix-merge
```

### 3. 测试 API
```bash
# 测试用户注册
curl -X POST http://localhost:9080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{"username": "demo", "email": "demo@example.com", "password": "demo123"}'
```

---

## 📐 核心架构

本项目通过 **Apache APISIX** 实现 **REST to gRPC** 的无感转码，采用 **etcd** 作为动态配置中心。

- **API Gateway**: 统一入口、认证、转码
- **Microservices**: Go 实现的业务逻辑
- **Infrastructure**: etcd, PostgreSQL, MongoDB, Redis

---

## 📚 文档指南

我们提供了详尽的文档体系，帮助你从零构建微服务：

- **[快速入门](./docs/README.md)** - 学习路径与文档索引
- **[核心概念](./docs/CORE-CONCEPTS.md)** - APISIX, gRPC, etcd 实战详解
- **[架构设计](./docs/ARCHITECTURE.md)** - 分层架构与系统扩展
- **[API 参考](./docs/API-REFERENCE.md)** - 接口定义与错误码

---

## 🔧 常用快捷命令

| 命令 | 说明 |
|------|------|
| `make run` | 启动所有 Docker 服务 |
| `make stop` | 停止并移除容器 |
| `make update-apisix-merge` | **[重要]** 合并并同步配置到 APISIX |
| `make new-service` | 创建新的微服务脚手架 |
| `make proto` | 生成 Protobuf 代码 |

---

## 🌐 服务访问地址

- **API Gateway**: `http://localhost:9080`
- **APISIX Admin**: `http://localhost:9180` (Key: `edd1c9f034335f136f87ad84b625c8f1`)
- **Dashboard**: `http://localhost:9000`

---
*更多详细内容请访问 [docs/ 目录](./docs)*
