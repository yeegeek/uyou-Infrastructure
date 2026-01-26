# 📚 uyou-Infrastructure 完整文档

本目录包含 uyou 微服务架构的完整学习和维护文档。

## 📖 文档导航

### 🚀 快速开始
- **[主文档 README.md](../README.md)** - 5分钟快速开始和完整使用指南

### 📐 架构设计
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - 系统架构设计详解
- **[MICROSERVICE-PATTERNS.md](./MICROSERVICE-PATTERNS.md)** - 微服务设计模式和最佳实践

### 🔧 核心概念
- **[CORE-CONCEPTS.md](./CORE-CONCEPTS.md)** - 核心技术概念详解（必读）
  - API Gateway 原理
  - gRPC 和 Protocol Buffers
  - REST to gRPC 转码机制
  - etcd 配置中心
  - 服务发现和负载均衡

### 🔐 认证授权
- **[JWT-AUTH-FLOW.md](./JWT-AUTH-FLOW.md)** - JWT 认证流程详解
- **[CONSUMER-KEY-EXPLANATION.md](./CONSUMER-KEY-EXPLANATION.md)** - Consumer Key 使用说明
- **[INTERFACE-SEPARATION.md](./INTERFACE-SEPARATION.md)** - 接口隔离和权限设计

### 🛠️ 开发指南
- **[DEVELOPMENT-GUIDE.md](./DEVELOPMENT-GUIDE.md)** - 完整开发指南
  - 环境搭建
  - 本地开发流程
  - 调试技巧
  - 代码规范

- **[SERVICE-SCAFFOLD-GUIDE.md](./SERVICE-SCAFFOLD-GUIDE.md)** - 微服务脚手架使用指南
  - 如何创建新服务
  - 项目结构说明
  - 代码生成器使用

### 📡 API 文档
- **[API-REFERENCE.md](./API-REFERENCE.md)** - 完整 API 接口文档
  - User Service API
  - Order Service API
  - Feed Service API
  - 错误码说明

### 🔍 运维指南
- **[OPERATIONS-GUIDE.md](./OPERATIONS-GUIDE.md)** - 运维和故障排查
  - 部署流程
  - 监控告警
  - 日志分析
  - 常见问题解决

### 📊 性能优化
- **[PERFORMANCE-OPTIMIZATION.md](./PERFORMANCE-OPTIMIZATION.md)** - 性能优化指南
  - 缓存策略
  - 数据库优化
  - 并发处理
  - 性能测试

## 🎓 学习路径

### 初级（1-2天）
1. 阅读主 README.md，理解整体架构
2. 学习 CORE-CONCEPTS.md，掌握核心概念
3. 跟随 DEVELOPMENT-GUIDE.md 搭建环境
4. 运行示例，测试 API

### 中级（3-5天）
1. 深入学习 ARCHITECTURE.md，理解设计决策
2. 阅读 MICROSERVICE-PATTERNS.md，学习设计模式
3. 使用 SERVICE-SCAFFOLD-GUIDE.md 创建新服务
4. 实现自定义业务逻辑

### 高级（1-2周）
1. 学习 PERFORMANCE-OPTIMIZATION.md，优化系统性能
2. 阅读 OPERATIONS-GUIDE.md，掌握运维技能
3. 实现复杂的微服务间调用
4. 搭建监控和日志系统

## 🔗 外部资源

- [Apache APISIX 官方文档](https://apisix.apache.org/docs/)
- [gRPC 官方文档](https://grpc.io/docs/)
- [Protocol Buffers 指南](https://protobuf.dev/)
- [etcd 官方文档](https://etcd.io/docs/)
- [Go 微服务最佳实践](https://github.com/golang-standards/project-layout)

## 📝 文档维护

文档更新流程：
1. 在对应的 `.md` 文件中修改
2. 提交 Git commit
3. 推送到远程仓库
4. 通知团队成员

## 💡 贡献指南

欢迎贡献文档改进！请遵循以下规范：
- 使用清晰的标题和章节
- 提供代码示例和图表
- 保持文档简洁易懂
- 及时更新过时内容
