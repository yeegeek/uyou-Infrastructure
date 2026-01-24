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
# 生成 user 服务的路由配置
make generate-route SERVICE=user

# 生成 order 服务的路由配置
make generate-route SERVICE=order
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

## 注意事项

1. 确保路由名称（`name` 字段）唯一
2. 确保 URI 路径不冲突
3. Proto ID 需要与 APISIX 中的 proto 定义一致
