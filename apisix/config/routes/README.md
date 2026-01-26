# APISIX 路由配置目录

此目录用于存放各微服务的路由配置片段。

## 使用方式

### 方式 1: 手动创建配置文件

每个微服务可以在这里创建自己的路由配置文件：

```yaml
# user-routes.yaml
routes:
  - name: user-register
    uri: /api/v1/users/register
    methods: [POST]
    upstream:
      nodes:
        "user-service:50051": 1
    plugins:
      grpc-transcode:
        proto_id: "1"
        service: user.UserService
        method: Register
```

### 方式 2: 自动生成配置

使用脚本从 proto 文件自动生成：

```bash

# 生成所有服务的路由配置
make generate-route
# 生成 user 服务的路由配置
make generate-route SERVICE=user
```

### 部署配置

合并所有配置文件并推送到 APISIX：

```bash
# 使用合并脚本
make update-apisix-merge

# 或直接运行脚本
./scripts/merge-apisix-configs.sh
```

## 文件命名规范

- `<service-name>-routes.yaml` - 服务路由配置
- 例如: `user-routes.yaml`, `order-routes.yaml`

## 接口分类和认证

### 公共接口 vs 内部接口

此目录中的路由配置**只包含公共接口**，这些接口通过 APISIX 网关暴露给客户端。

- **公共接口**：通过 APISIX 暴露，使用 JWT 认证
  - 文件：`*-routes.yaml`
  - 访问方式：`http://gateway:9080/api/v1/...`
  - 认证：JWT Token（在 HTTP Header 中）

- **内部接口**：不通过 APISIX，直接 gRPC 调用
  - 文件：`*-internal.proto`（不在路由配置中）
  - 访问方式：`grpc://service:port`（直接连接）
  - 认证：依赖内网安全（无需额外认证）

详细说明：参见 [docs/INTERFACE-SEPARATION.md](../../docs/INTERFACE-SEPARATION.md)

### JWT 认证配置

路由配置中的 `jwt-auth` 插件用于启用 JWT 认证：

```yaml
routes:
  # 公开接口：不需要 JWT（注册、登录）
  - name: user-register
    uri: /api/v1/users/register
    methods: [POST]
    plugins:
      # 注意：没有 jwt-auth 插件
      grpc-transcode:
        # ...

  # 受保护接口：需要 JWT
  - name: user-getuser
    uri: /api/v1/users/*
    methods: [GET]
    plugins:
      jwt-auth: {}  # 启用 JWT 认证
      grpc-transcode:
        # ...
```

**公开接口**（不需要 JWT）：
- 用户注册：`/api/v1/users/register`
- 用户登录：`/api/v1/users/login`

**受保护接口**（需要 JWT）：
- 所有其他接口都需要在 Header 中携带 JWT Token
- Token 格式：`Authorization: Bearer <token>`

### 自动生成时的认证规则

使用 `generate-route-config.sh` 脚本自动生成路由配置时，脚本会根据方法名自动判断是否需要 JWT 认证：

- `Register`、`Login` → 不需要 JWT（公开接口）
- `Get*`、`List*`、`Create*`、`Update*`、`Delete*` → 需要 JWT（受保护接口）

生成后请根据实际业务需求手动调整。

## 注意事项

1. 确保路由名称（`name` 字段）唯一
2. 确保 URI 路径不冲突
3. Proto ID 需要与 APISIX 中的 proto 定义一致
4. **只配置公共接口**，内部接口不在此目录配置
5. 公开接口（注册、登录）不需要 `jwt-auth` 插件
6. 受保护接口必须添加 `jwt-auth: {}` 插件

## 相关文档

- [接口分离设计](../../docs/INTERFACE-SEPARATION.md) - 了解公共接口和内部接口的区别
- [README.md](../../README.md) - 项目总体文档
