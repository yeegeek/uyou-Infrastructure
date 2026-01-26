# CI/CD 部署完整指南

本文档详细介绍如何使用 GitHub Actions、Docker 和 Kubernetes 部署 uyou 微服务。

---

## 目录

1. [概述](#概述)
2. [CI/CD 流程](#cicd-流程)
3. [GitHub Actions 配置](#github-actions-配置)
4. [Docker 构建](#docker-构建)
5. [Kubernetes 部署](#kubernetes-部署)
6. [Helm Chart 部署](#helm-chart-部署)
7. [环境配置](#环境配置)
8. [最佳实践](#最佳实践)
9. [故障排查](#故障排查)

---

## 概述

### CI/CD 架构

```
代码提交 → GitHub Actions → 测试 → 构建 → Docker 镜像 → 推送到仓库 → 部署到 K8s
```

### 支持的环境

- **开发环境 (Development)**: 自动部署 `develop` 分支
- **生产环境 (Production)**: 自动部署 `v*` 标签

### 技术栈

| 组件 | 技术 | 说明 |
|------|------|------|
| CI/CD | GitHub Actions | 自动化构建和部署 |
| 容器化 | Docker | 多阶段构建，优化镜像大小 |
| 编排 | Kubernetes | 容器编排和管理 |
| 包管理 | Helm | Kubernetes 应用打包 |
| 镜像仓库 | GitHub Container Registry | 存储 Docker 镜像 |

---

## CI/CD 流程

### 完整流程图

```
┌─────────────┐
│  代码提交    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  代码检查    │ ← golangci-lint
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  运行测试    │ ← go test
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  构建二进制  │ ← go build
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  构建镜像    │ ← Docker build
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  推送镜像    │ ← Docker push
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  安全扫描    │ ← Trivy
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  部署到 K8s  │ ← kubectl/Helm
└─────────────┘
```

### 触发条件

#### 自动触发

| 事件 | 分支/标签 | 执行任务 |
|------|----------|---------|
| Push | `main` | 测试 + 构建 + 部署到生产 |
| Push | `develop` | 测试 + 构建 + 部署到开发 |
| Push | `v*` 标签 | 测试 + 构建 + 部署到生产 |
| Pull Request | `main`, `develop` | 测试 + 构建 |

#### 手动触发

```bash
# 通过 GitHub UI 手动触发
# Actions → 选择 workflow → Run workflow
```

---

## GitHub Actions 配置

### 1. 配置文件位置

```
.github/
└── workflows/
    └── ci-cd.yml
```

### 2. 核心 Jobs

#### Test Job

```yaml
test:
  name: Test
  runs-on: ubuntu-latest
  steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Set up Go
      uses: actions/setup-go@v5
      with:
        go-version: '1.21'
    
    - name: Run tests
      run: go test -v -race -coverprofile=coverage.out ./...
```

**功能**：
- 代码检出
- Go 环境设置
- 依赖下载
- 代码检查（golangci-lint）
- 单元测试
- 覆盖率上传

#### Build Job

```yaml
build:
  name: Build
  needs: test
  steps:
    - name: Build binary
      run: |
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -ldflags="-w -s" -o bin/service cmd/server/main.go
```

**功能**：
- 编译 Go 二进制文件
- 静态链接（CGO_ENABLED=0）
- 优化二进制大小（-ldflags="-w -s"）

#### Docker Job

```yaml
docker:
  name: Build and Push Docker Image
  needs: build
  steps:
    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

**功能**：
- 构建 Docker 镜像
- 推送到 GitHub Container Registry
- 使用 GitHub Actions 缓存加速构建
- 支持多平台（amd64/arm64）

#### Deploy Job

```yaml
deploy-prod:
  name: Deploy to Production
  needs: docker
  if: startsWith(github.ref, 'refs/tags/v')
  steps:
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/service \
          service=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:$VERSION
```

**功能**：
- 更新 Kubernetes Deployment
- 等待部署完成
- 验证部署状态

### 3. 配置 Secrets

在 GitHub 仓库设置中添加以下 Secrets：

```bash
# GitHub Settings → Secrets and variables → Actions → New repository secret
```

| Secret 名称 | 说明 | 示例 |
|------------|------|------|
| `KUBECONFIG_DEV` | 开发环境 kubeconfig（base64） | `cat ~/.kube/config \| base64` |
| `KUBECONFIG_PROD` | 生产环境 kubeconfig（base64） | `cat ~/.kube/config \| base64` |
| `DOCKER_USERNAME` | Docker 用户名（可选） | `username` |
| `DOCKER_PASSWORD` | Docker 密码（可选） | `password` |

### 4. 配置环境

```bash
# GitHub Settings → Environments → New environment
```

创建两个环境：
- **development**: 开发环境
- **production**: 生产环境（添加审批规则）

---

## Docker 构建

### 1. Dockerfile 多阶段构建

```dockerfile
# 构建阶段
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o service cmd/server/main.go

# 运行阶段
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /build/service .
COPY --from=builder /build/config ./config
EXPOSE 50051
ENTRYPOINT ["./service"]
```

**优势**：
- **镜像小**：最终镜像只包含二进制文件和运行时依赖
- **安全**：基于 Alpine，攻击面小
- **快速**：利用 Docker 缓存加速构建

### 2. 本地构建

```bash
# 构建镜像
docker build -t user-service:latest -f deployments/docker/Dockerfile .

# 运行容器
docker run -p 50051:50051 user-service:latest

# 查看日志
docker logs -f <container_id>
```

### 3. 使用 docker-compose

```bash
# 启动所有服务
docker compose -f deployments/docker/docker-compose.yml up -d

# 查看日志
docker compose logs -f

# 停止服务
docker compose down
```

### 4. 镜像优化

#### 减小镜像大小

```dockerfile
# 使用 Alpine 基础镜像
FROM alpine:latest

# 只复制必要文件
COPY --from=builder /build/service .

# 清理缓存
RUN apk add --no-cache ca-certificates && \
    rm -rf /var/cache/apk/*
```

#### 构建参数

```bash
# 注入版本信息
docker build \
  --build-arg VERSION=v1.0.0 \
  --build-arg BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  -t user-service:v1.0.0 .
```

---

## Kubernetes 部署

### 1. 部署架构

```
┌─────────────────────────────────────────┐
│           Kubernetes Cluster            │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │         Namespace: prod           │ │
│  │                                   │ │
│  │  ┌─────────────────────────────┐ │ │
│  │  │      Deployment (3 pods)    │ │ │
│  │  │  ┌───┐  ┌───┐  ┌───┐       │ │ │
│  │  │  │Pod│  │Pod│  │Pod│       │ │ │
│  │  │  └───┘  └───┘  └───┘       │ │ │
│  │  └─────────────────────────────┘ │ │
│  │                                   │ │
│  │  ┌─────────────────────────────┐ │ │
│  │  │         Service             │ │ │
│  │  │    (ClusterIP: 50051)       │ │ │
│  │  └─────────────────────────────┘ │ │
│  │                                   │ │
│  │  ┌─────────────────────────────┐ │ │
│  │  │      ConfigMap / Secret     │ │ │
│  │  └─────────────────────────────┘ │ │
│  │                                   │ │
│  │  ┌─────────────────────────────┐ │ │
│  │  │           HPA               │ │ │
│  │  │    (min: 3, max: 10)        │ │ │
│  │  └─────────────────────────────┘ │ │
│  └───────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 2. 部署步骤

#### 方法 1：使用 kubectl

```bash
# 1. 创建命名空间
kubectl create namespace production

# 2. 应用配置
kubectl apply -f deployments/kubernetes/serviceaccount.yaml
kubectl apply -f deployments/kubernetes/configmap.yaml
kubectl apply -f deployments/kubernetes/secret.yaml

# 3. 部署应用
kubectl apply -f deployments/kubernetes/deployment.yaml
kubectl apply -f deployments/kubernetes/service.yaml

# 4. 配置自动扩展
kubectl apply -f deployments/kubernetes/hpa.yaml
kubectl apply -f deployments/kubernetes/pdb.yaml

# 5. 验证部署
kubectl get pods -n production
kubectl get svc -n production
```

#### 方法 2：使用 Kustomize

```bash
# 部署
kubectl apply -k deployments/kubernetes/

# 查看生成的 YAML
kubectl kustomize deployments/kubernetes/
```

### 3. 配置管理

#### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-service-config
data:
  server.mode: "production"
  database.host: "postgres-service"
  redis.host: "redis-service"
  logger.level: "info"
```

**用途**：存储非敏感配置

#### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: user-service-secret
type: Opaque
stringData:
  database.password: "CHANGE_ME"
  jwt.secret: "CHANGE_ME"
```

**用途**：存储敏感信息（密码、密钥）

**创建 Secret**：

```bash
# 从文件创建
kubectl create secret generic user-service-secret \
  --from-file=database.password=./db-password.txt \
  --from-file=jwt.secret=./jwt-secret.txt

# 从字面值创建
kubectl create secret generic user-service-secret \
  --from-literal=database.password=mypassword \
  --from-literal=jwt.secret=mysecret
```

### 4. 健康检查

#### Liveness Probe（存活探针）

```yaml
livenessProbe:
  exec:
    command:
      - grpc_health_probe
      - -addr=:50051
  initialDelaySeconds: 15
  periodSeconds: 20
```

**作用**：检测容器是否存活，失败则重启容器

#### Readiness Probe（就绪探针）

```yaml
readinessProbe:
  exec:
    command:
      - grpc_health_probe
      - -addr=:50051
  initialDelaySeconds: 5
  periodSeconds: 10
```

**作用**：检测容器是否就绪，未就绪则不转发流量

#### Startup Probe（启动探针）

```yaml
startupProbe:
  exec:
    command:
      - grpc_health_probe
      - -addr=:50051
  failureThreshold: 30
  periodSeconds: 10
```

**作用**：检测容器启动，避免慢启动应用被误杀

### 5. 资源管理

#### 资源请求和限制

```yaml
resources:
  requests:
    cpu: 100m      # 最少需要 0.1 核
    memory: 128Mi  # 最少需要 128MB
  limits:
    cpu: 500m      # 最多使用 0.5 核
    memory: 512Mi  # 最多使用 512MB
```

**最佳实践**：
- **requests**: 保证资源，用于调度决策
- **limits**: 防止资源滥用，超过限制会被限流或 OOM

#### 水平自动扩展（HPA）

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          averageUtilization: 70
```

**触发条件**：
- CPU 使用率超过 70%
- 内存使用率超过 80%

### 6. 滚动更新

```bash
# 更新镜像
kubectl set image deployment/user-service \
  user-service=ghcr.io/user/user-service:v1.1.0

# 查看更新状态
kubectl rollout status deployment/user-service

# 查看更新历史
kubectl rollout history deployment/user-service

# 回滚到上一个版本
kubectl rollout undo deployment/user-service

# 回滚到指定版本
kubectl rollout undo deployment/user-service --to-revision=2
```

### 7. 监控和日志

#### 查看 Pod 状态

```bash
# 列出所有 Pod
kubectl get pods -n production

# 查看 Pod 详情
kubectl describe pod <pod-name> -n production

# 查看 Pod 日志
kubectl logs <pod-name> -n production

# 实时查看日志
kubectl logs -f <pod-name> -n production

# 查看前一个容器的日志（容器重启后）
kubectl logs <pod-name> -n production --previous
```

#### 进入容器

```bash
# 进入容器 shell
kubectl exec -it <pod-name> -n production -- /bin/sh

# 执行命令
kubectl exec <pod-name> -n production -- ls -la /app
```

---

## Helm Chart 部署

### 1. Helm 简介

Helm 是 Kubernetes 的包管理器，类似于 apt/yum。

**优势**：
- **模板化**：参数化配置，支持多环境
- **版本管理**：支持回滚
- **依赖管理**：管理应用依赖
- **可重用**：一次编写，多次部署

### 2. Helm Chart 结构

```
helm/
├── Chart.yaml              # Chart 元数据
├── values.yaml             # 默认配置
├── values-dev.yaml         # 开发环境配置
├── values-prod.yaml        # 生产环境配置
└── templates/              # Kubernetes 资源模板
    ├── _helpers.tpl        # 辅助模板
    ├── deployment.yaml     # Deployment 模板
    ├── service.yaml        # Service 模板
    ├── configmap.yaml      # ConfigMap 模板
    ├── secret.yaml         # Secret 模板
    ├── hpa.yaml            # HPA 模板
    └── tests/              # 测试
        └── test-connection.yaml
```

### 3. 部署步骤

#### 安装 Helm

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 验证安装
helm version
```

#### 部署到开发环境

```bash
# 1. 添加仓库（如果使用远程 Chart）
helm repo add uyou https://charts.uyou.com
helm repo update

# 2. 安装 Chart
helm install user-service ./helm \
  --namespace development \
  --create-namespace \
  --values helm/values-dev.yaml

# 3. 查看状态
helm status user-service -n development

# 4. 查看生成的资源
helm get manifest user-service -n development
```

#### 部署到生产环境

```bash
# 使用生产配置
helm install user-service ./helm \
  --namespace production \
  --create-namespace \
  --values helm/values-prod.yaml \
  --set image.tag=v1.0.0
```

#### 升级部署

```bash
# 升级到新版本
helm upgrade user-service ./helm \
  --namespace production \
  --values helm/values-prod.yaml \
  --set image.tag=v1.1.0

# 查看升级历史
helm history user-service -n production

# 回滚到上一个版本
helm rollback user-service -n production

# 回滚到指定版本
helm rollback user-service 2 -n production
```

#### 卸载部署

```bash
# 卸载 Release
helm uninstall user-service -n production

# 卸载并删除所有资源
helm uninstall user-service -n production --wait
```

### 4. 配置管理

#### values.yaml（默认配置）

```yaml
replicaCount: 3

image:
  repository: ghcr.io/user/user-service
  tag: latest

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

#### values-prod.yaml（生产环境覆盖）

```yaml
replicaCount: 5

image:
  tag: v1.0.0

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 20
```

#### 命令行覆盖

```bash
# 覆盖单个值
helm install user-service ./helm --set image.tag=v1.2.0

# 覆盖多个值
helm install user-service ./helm \
  --set image.tag=v1.2.0 \
  --set replicaCount=5 \
  --set resources.requests.cpu=200m
```

### 5. 模板调试

```bash
# 渲染模板（不部署）
helm template user-service ./helm \
  --values helm/values-prod.yaml

# 模拟安装（dry-run）
helm install user-service ./helm \
  --dry-run --debug \
  --values helm/values-prod.yaml

# 验证 Chart
helm lint ./helm
```

---

## 环境配置

### 1. 开发环境

**特点**：
- 自动部署 `develop` 分支
- 单副本
- 资源限制较低
- 日志级别 Debug

**配置**：

```yaml
# values-dev.yaml
replicaCount: 1

config:
  server:
    mode: development
  logger:
    level: debug

autoscaling:
  enabled: false
```

### 2. 生产环境

**特点**：
- 手动部署或标签触发
- 多副本 + HPA
- 资源限制较高
- 日志级别 Info
- 启用监控和追踪

**配置**：

```yaml
# values-prod.yaml
replicaCount: 5

config:
  server:
    mode: production
  logger:
    level: info

autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 20

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

---

## 最佳实践

### 1. 版本管理

#### 语义化版本

```
v<major>.<minor>.<patch>

v1.0.0  # 初始版本
v1.1.0  # 新功能
v1.1.1  # Bug 修复
v2.0.0  # 重大更新
```

#### Git 标签

```bash
# 创建标签
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# 删除标签
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

### 2. 镜像管理

#### 镜像标签策略

```
ghcr.io/user/user-service:latest          # 最新版本
ghcr.io/user/user-service:v1.0.0          # 语义化版本
ghcr.io/user/user-service:main-abc123     # 分支 + commit
ghcr.io/user/user-service:pr-123          # PR 编号
```

**建议**：
- ✅ 生产环境使用固定版本标签（v1.0.0）
- ✅ 开发环境可以使用 latest
- ❌ 避免在生产环境使用 latest

#### 镜像清理

```bash
# 删除旧镜像（保留最近 10 个）
# 使用 GitHub Packages 的自动清理策略
```

### 3. 安全

#### 最小权限原则

```yaml
# 使用非 root 用户
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  capabilities:
    drop:
      - ALL
```

#### Secret 管理

```bash
# 使用 Sealed Secrets（加密 Secret）
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# 使用外部 Secret 管理器
# - AWS Secrets Manager
# - HashiCorp Vault
# - Azure Key Vault
```

#### 镜像扫描

```yaml
# Trivy 扫描
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE }}
    format: 'sarif'
    output: 'trivy-results.sarif'
```

### 4. 监控和告警

#### Prometheus 指标

```go
// 在代码中暴露指标
http.Handle("/metrics", promhttp.Handler())
```

```yaml
# Pod 注解
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9090"
  prometheus.io/path: "/metrics"
```

#### 日志聚合

```yaml
# 使用 Fluentd/Fluent Bit 收集日志
# 发送到 Elasticsearch/Loki
```

### 5. 成本优化

#### 资源请求优化

```bash
# 查看实际资源使用
kubectl top pods -n production

# 根据实际使用调整 requests/limits
```

#### 节点亲和性

```yaml
# 使用 Spot 实例
nodeSelector:
  node.kubernetes.io/instance-type: spot
```

---

## 故障排查

### 1. Pod 无法启动

#### 问题：ImagePullBackOff

```bash
# 查看详情
kubectl describe pod <pod-name>

# 常见原因
# - 镜像不存在
# - 镜像仓库认证失败
# - 镜像标签错误

# 解决方案
# 1. 检查镜像名称和标签
# 2. 验证镜像仓库凭证
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token>
```

#### 问题：CrashLoopBackOff

```bash
# 查看日志
kubectl logs <pod-name> --previous

# 常见原因
# - 应用启动失败
# - 配置错误
# - 依赖服务不可用

# 解决方案
# 1. 检查应用日志
# 2. 验证配置
# 3. 检查依赖服务
```

### 2. 服务无法访问

#### 问题：Service 无法访问

```bash
# 检查 Service
kubectl get svc -n production
kubectl describe svc user-service -n production

# 检查 Endpoints
kubectl get endpoints user-service -n production

# 测试连接
kubectl run test-pod --image=busybox --rm -it -- sh
# 在 Pod 内测试
wget -O- http://user-service:50051
```

### 3. 性能问题

#### 问题：CPU/内存使用率高

```bash
# 查看资源使用
kubectl top pods -n production

# 查看 HPA 状态
kubectl get hpa -n production

# 解决方案
# 1. 增加副本数
kubectl scale deployment user-service --replicas=10

# 2. 调整资源限制
kubectl set resources deployment user-service \
  --limits=cpu=1000m,memory=1Gi \
  --requests=cpu=200m,memory=256Mi
```

### 4. 部署失败

#### 问题：Deployment 更新卡住

```bash
# 查看部署状态
kubectl rollout status deployment/user-service

# 查看事件
kubectl get events -n production --sort-by='.lastTimestamp'

# 回滚
kubectl rollout undo deployment/user-service
```

### 5. 常用调试命令

```bash
# 查看所有资源
kubectl get all -n production

# 查看 Pod 详情
kubectl describe pod <pod-name> -n production

# 查看日志
kubectl logs <pod-name> -n production -f

# 进入容器
kubectl exec -it <pod-name> -n production -- /bin/sh

# 端口转发
kubectl port-forward <pod-name> 50051:50051 -n production

# 查看资源使用
kubectl top nodes
kubectl top pods -n production

# 查看事件
kubectl get events -n production --watch
```

---

## 总结

本指南涵盖了从代码提交到生产部署的完整 CI/CD 流程。

### 关键要点

1. **自动化**：使用 GitHub Actions 实现完全自动化
2. **容器化**：使用 Docker 多阶段构建优化镜像
3. **编排**：使用 Kubernetes 管理容器生命周期
4. **包管理**：使用 Helm 简化部署和配置管理
5. **监控**：集成 Prometheus 和日志聚合
6. **安全**：镜像扫描、最小权限、Secret 管理

### 下一步

- 阅读 [运维指南](OPERATIONS-GUIDE.md)
- 配置监控和告警
- 实施灾难恢复计划
- 优化成本和性能

---

**最后更新**: 2026-01-26
