# 📚 uyou-Infrastructure 完整文档

本目录包含 uyou 微服务架构的完整学习和维护文档。

## 📖 文档导航

### 🚀 快速开始
- **[主文档 README.md](../README.md)** - 5分钟快速开始和完整使用指南

### 📐 架构设计
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - 系统架构设计详解
- **[PROJECT-SUMMARY.md](./PROJECT-SUMMARY.md)** - 项目概览和总结

### 🔧 核心概念
- **[CORE-CONCEPTS.md](./CORE-CONCEPTS.md)** - 核心技术概念详解（必读）
  - API Gateway 原理
  - gRPC 和 Protocol Buffers
  - REST to gRPC 转码机制
  - etcd 配置中心
  - 服务发现和负载均衡

### 🛠️ 开发指南
- **[../service-scaffold/README.md](../service-scaffold/README.md)** - 微服务脚手架使用指南
  - 如何创建新服务
  - 项目结构说明
  - 代码生成器使用

### 📡 API 文档
- **[API-REFERENCE.md](./API-REFERENCE.md)** - 完整 API 接口文档
  - User Service API
  - Order Service API
  - Feed Service API
  - 错误码说明

## 🎓 学习路径

### 初级
1. 阅读主 README.md，理解整体架构
2. 学习 CORE-CONCEPTS.md，掌握核心概念
3. 跟随 DEVELOPMENT-GUIDE.md 搭建环境
4. 运行示例，测试 API

### 中级
1. 深入学习 ARCHITECTURE.md，理解设计决策
2. 阅读 PROJECT-SUMMARY.md，了解项目整体情况
3. 使用 service-scaffold/README.md 创建新服务
4. 实现自定义业务逻辑

### 高级
1. 阅读主 README.md 的运维部分，掌握故障排查技能
2. 实现复杂的微服务间调用
3. 搭建监控和日志系统

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
