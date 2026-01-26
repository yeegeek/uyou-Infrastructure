package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/template"
)

// ServiceConfig 服务配置
type ServiceConfig struct {
	ServiceName   string // 服务名称，如 User
	EntityName    string // 实体名称，如 User
	ModulePath    string // Go 模块路径
	GitRepo       string // Git 仓库地址
	Port          int    // 服务端口
	UsePostgreSQL bool   // 是否使用 PostgreSQL
	UseMongoDB    bool   // 是否使用 MongoDB
	UseQueue      bool   // 是否使用消息队列
	DatabaseName  string // 数据库名称
	TableName     string // 表名称
	CachePrefix   string // 缓存前缀
	RedisDB       int    // Redis DB
}

func main() {
	fmt.Println("🚀 uyou 微服务生成器")
	fmt.Println("====================")
	fmt.Println()

	// 1. 收集用户输入
	config := collectInput()

	// 2. 确认配置
	if !confirmConfig(config) {
		fmt.Println("❌ 已取消")
		return
	}

	// 3. 生成服务
	if err := generateService(config); err != nil {
		fmt.Printf("❌ 生成失败: %v\n", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println("✅ 服务生成成功！")
	fmt.Println()
	fmt.Println("📝 后续步骤：")
	fmt.Printf("   1. cd %s\n", config.ServiceName)
	fmt.Println("   2. 编辑 api/proto/*.proto 定义 API")
	fmt.Println("   3. make proto  # 生成 Proto 代码")
	fmt.Println("   4. 实现业务逻辑")
	fmt.Println("   5. make build  # 构建服务")
	fmt.Println("   6. make run    # 运行服务")
}

// collectInput 收集用户输入
func collectInput() *ServiceConfig {
	reader := bufio.NewReader(os.Stdin)
	config := &ServiceConfig{}

	// 服务名称
	config.ServiceName = readInput(reader, "服务名称 (如 User, Order, Feed)", "User")
	config.EntityName = config.ServiceName

	// Git 仓库
	config.GitRepo = readInput(reader, "Git 仓库地址 (如 github.com/uyou/uyou-user-service)", "")

	// 模块路径
	if config.GitRepo != "" {
		config.ModulePath = config.GitRepo
	} else {
		config.ModulePath = readInput(reader, "Go 模块路径", fmt.Sprintf("github.com/uyou/uyou-%s-service", strings.ToLower(config.ServiceName)))
	}

	// 端口
	portStr := readInput(reader, "gRPC 端口", "50051")
	fmt.Sscanf(portStr, "%d", &config.Port)

	// 数据库类型
	dbType := readInput(reader, "数据库类型 (postgres/mongodb)", "postgres")
	config.UsePostgreSQL = strings.ToLower(dbType) == "postgres"
	config.UseMongoDB = strings.ToLower(dbType) == "mongodb"

	// 数据库名称
	config.DatabaseName = readInput(reader, "数据库名称", strings.ToLower(config.ServiceName)+"db")

	if config.UsePostgreSQL {
		config.TableName = readInput(reader, "表名称", strings.ToLower(config.ServiceName)+"s")
	}

	// Redis DB
	redisDBStr := readInput(reader, "Redis DB (0-15)", "0")
	fmt.Sscanf(redisDBStr, "%d", &config.RedisDB)

	// 缓存前缀
	config.CachePrefix = readInput(reader, "缓存前缀", strings.ToLower(config.ServiceName))

	// 消息队列
	useQueue := readInput(reader, "是否使用消息队列? (y/n)", "n")
	config.UseQueue = strings.ToLower(useQueue) == "y"

	return config
}

// readInput 读取用户输入
func readInput(reader *bufio.Reader, prompt, defaultValue string) string {
	if defaultValue != "" {
		fmt.Printf("%s [%s]: ", prompt, defaultValue)
	} else {
		fmt.Printf("%s: ", prompt)
	}

	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(input)

	if input == "" {
		return defaultValue
	}
	return input
}

// confirmConfig 确认配置
func confirmConfig(config *ServiceConfig) bool {
	fmt.Println()
	fmt.Println("📋 配置确认")
	fmt.Println("====================")
	fmt.Printf("服务名称: %s\n", config.ServiceName)
	fmt.Printf("模块路径: %s\n", config.ModulePath)
	fmt.Printf("Git 仓库: %s\n", config.GitRepo)
	fmt.Printf("端口: %d\n", config.Port)
	if config.UsePostgreSQL {
		fmt.Printf("数据库: PostgreSQL (%s)\n", config.DatabaseName)
		fmt.Printf("表名称: %s\n", config.TableName)
	} else if config.UseMongoDB {
		fmt.Printf("数据库: MongoDB (%s)\n", config.DatabaseName)
	}
	fmt.Printf("Redis DB: %d\n", config.RedisDB)
	fmt.Printf("缓存前缀: %s\n", config.CachePrefix)
	fmt.Printf("消息队列: %v\n", config.UseQueue)
	fmt.Println()

	reader := bufio.NewReader(os.Stdin)
	confirm := readInput(reader, "确认生成? (y/n)", "y")
	return strings.ToLower(confirm) == "y"
}

// generateService 生成服务
func generateService(config *ServiceConfig) error {
	serviceName := strings.ToLower(config.ServiceName) + "-service"
	serviceDir := filepath.Join("../", serviceName)

	fmt.Printf("📁 创建目录: %s\n", serviceDir)

	// 1. 创建目录结构
	dirs := []string{
		"cmd/server",
		"internal/handler",
		"internal/service",
		"internal/repository/cache",
		"internal/model/dto",
		"internal/middleware",
		"internal/validator",
		"internal/util",
		"internal/worker",
		"pkg/config",
		"pkg/database",
		"pkg/logger",
		"pkg/errors",
		"api/proto",
		"config",
		"migrations",
		"scripts",
		"deployments/docker",
		"docs",
		"test/integration",
	}

	for _, dir := range dirs {
		fullPath := filepath.Join(serviceDir, dir)
		if err := os.MkdirAll(fullPath, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", fullPath, err)
		}
	}

	// 2. 生成文件
	templates := map[string]string{
		"cmd/server/main.go":                          "template/cmd/server/main.go.tmpl",
		"pkg/config/config.go":                        "template/pkg/config/config.go.tmpl",
		"pkg/logger/logger.go":                        "template/pkg/logger/logger.go.tmpl",
		"pkg/database/redis.go":                       "template/pkg/database/redis.go.tmpl",
		"pkg/errors/errors.go":                        "template/pkg/errors/errors.go.tmpl",
		"internal/handler/handler.go":                 "template/internal/handler/handler.go.tmpl",
		"internal/service/service.go":                 "template/internal/service/service.go.tmpl",
		"internal/model/model.go":                     "template/internal/model/model.go.tmpl",
		"internal/validator/validator.go":             "template/internal/validator/validator.go.tmpl",
		"internal/middleware/logging.go":              "template/internal/middleware/logging.go.tmpl",
		"internal/middleware/recovery.go":             "template/internal/middleware/recovery.go.tmpl",
		"internal/middleware/tracing.go":              "template/internal/middleware/tracing.go.tmpl",
		"internal/middleware/validator.go":            "template/internal/middleware/validator.go.tmpl",
		"internal/repository/cache/cache_repository.go": "template/internal/repository/cache/cache_repository.go.tmpl",
		"config/config.yaml":                          "template/config/config.yaml.tmpl",
		".github/workflows/ci-cd.yml":                  "template/.github/workflows/ci-cd.yml.tmpl",
		".golangci.yml":                                "template/.golangci.yml.tmpl",
		".dockerignore":                                "template/.dockerignore.tmpl",
		"deployments/docker/Dockerfile":                "template/deployments/docker/Dockerfile.tmpl",
		"deployments/docker/docker-compose.yml":       "template/deployments/docker/docker-compose.yml.tmpl",
	}

	if config.UsePostgreSQL {
		templates["pkg/database/postgres.go"] = "template/pkg/database/postgres.go.tmpl"
		templates["internal/repository/repository.go"] = "template/internal/repository/repository_postgres.go.tmpl"
	}

	if config.UseMongoDB {
		templates["pkg/database/mongodb.go"] = "template/pkg/database/mongodb.go.tmpl"
	}

	for dst, src := range templates {
		fmt.Printf("📝 生成文件: %s\n", dst)
		if err := generateFile(serviceDir, dst, src, config); err != nil {
			return fmt.Errorf("failed to generate %s: %w", dst, err)
		}
	}

	// 3. 创建 Kubernetes 配置目录
	kubeDirs := []string{
		"deployments/kubernetes",
		"helm/templates",
	}
	for _, dir := range kubeDirs {
		fullPath := filepath.Join(serviceDir, dir)
		if err := os.MkdirAll(fullPath, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", fullPath, err)
		}
	}

	// 4. 生成 go.mod
	if err := generateGoMod(serviceDir, config); err != nil {
		return fmt.Errorf("failed to generate go.mod: %w", err)
	}

	// 4. 生成 Makefile
	if err := generateMakefile(serviceDir, config); err != nil {
		return fmt.Errorf("failed to generate Makefile: %w", err)
	}

	// 5. 生成 README
	if err := generateReadme(serviceDir, config); err != nil {
		return fmt.Errorf("failed to generate README: %w", err)
	}

	// 6. 生成 Dockerfile
	if err := generateDockerfile(serviceDir, config); err != nil {
		return fmt.Errorf("failed to generate Dockerfile: %w", err)
	}

	// 7. 生成 Proto 示例
	if err := generateProtoExample(serviceDir, config); err != nil {
		return fmt.Errorf("failed to generate proto example: %w", err)
	}

	// 8. 初始化 Git（如果提供了仓库地址）
	if config.GitRepo != "" {
		fmt.Printf("🔧 初始化 Git 仓库\n")
		if err := initGit(serviceDir, config.GitRepo); err != nil {
			fmt.Printf("⚠️  Git 初始化失败: %v\n", err)
		}
	}

	return nil
}

// generateFile 生成文件
func generateFile(serviceDir, dst, src string, config *ServiceConfig) error {
	tmpl, err := template.ParseFiles(src)
	if err != nil {
		return err
	}

	dstPath := filepath.Join(serviceDir, dst)
	file, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer file.Close()

	return tmpl.Execute(file, config)
}

// generateGoMod 生成 go.mod
func generateGoMod(serviceDir string, config *ServiceConfig) error {
	content := fmt.Sprintf(`module %s

go 1.21

require (
	github.com/google/uuid v1.6.0
	github.com/lib/pq v1.10.9
	github.com/redis/go-redis/v9 v9.5.1
	github.com/spf13/viper v1.18.2
	go.mongodb.org/mongo-driver v1.13.1
	go.uber.org/zap v1.27.0
	google.golang.org/grpc v1.62.0
	google.golang.org/protobuf v1.32.0
)
`, config.ModulePath)

	return os.WriteFile(filepath.Join(serviceDir, "go.mod"), []byte(content), 0644)
}

// generateMakefile 生成 Makefile
func generateMakefile(serviceDir string, config *ServiceConfig) error {
	content := fmt.Sprintf(`.PHONY: proto build run test clean

proto:
	protoc --go_out=. --go-grpc_out=. api/proto/*.proto

build:
	go build -o bin/%s cmd/server/main.go

run:
	go run cmd/server/main.go

test:
	go test -v ./...

clean:
	rm -rf bin/
`, strings.ToLower(config.ServiceName)+"-service")

	return os.WriteFile(filepath.Join(serviceDir, "Makefile"), []byte(content), 0644)
}

// generateReadme 生成 README
func generateReadme(serviceDir string, config *ServiceConfig) error {
	content := fmt.Sprintf(`# %s Service

%s 微服务

## 快速开始

### 1. 生成 Proto 代码

`+"```bash"+`
make proto
`+"```"+`

### 2. 运行服务

`+"```bash"+`
make run
`+"```"+`

### 3. 测试

`+"```bash"+`
make test
`+"```"+`

## 配置

编辑 `+"`config/config.yaml`"+` 文件配置服务参数。

## 目录结构

- `+"`cmd/`"+` - 应用程序入口
- `+"`internal/`"+` - 私有代码
- `+"`pkg/`"+` - 公共代码
- `+"`api/proto/`"+` - Proto 定义
- `+"`config/`"+` - 配置文件
- `+"`migrations/`"+` - 数据库迁移

## 开发

1. 编辑 `+"`api/proto/*.proto`"+` 定义 API
2. 运行 `+"`make proto`"+` 生成代码
3. 实现业务逻辑
4. 编写测试
5. 构建和部署
`, config.ServiceName, config.ServiceName)

	return os.WriteFile(filepath.Join(serviceDir, "README.md"), []byte(content), 0644)
}

// generateDockerfile 生成 Dockerfile
func generateDockerfile(serviceDir string, config *ServiceConfig) error {
	content := fmt.Sprintf(`FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o bin/server cmd/server/main.go

FROM alpine:latest

WORKDIR /app

COPY --from=builder /app/bin/server .
COPY --from=builder /app/config ./config

EXPOSE %d

CMD ["./server"]
`, config.Port)

	return os.WriteFile(filepath.Join(serviceDir, "deployments/docker/Dockerfile"), []byte(content), 0644)
}

// generateProtoExample 生成 Proto 示例
func generateProtoExample(serviceDir string, config *ServiceConfig) error {
	content := fmt.Sprintf(`syntax = "proto3";

package %s;

option go_package = "%s/api/proto";

service %sService {
  rpc Create(Create%sRequest) returns (Create%sResponse);
  rpc Get(Get%sRequest) returns (Get%sResponse);
  rpc Update(Update%sRequest) returns (Update%sResponse);
  rpc Delete(Delete%sRequest) returns (Delete%sResponse);
  rpc List(List%sRequest) returns (List%sResponse);
}

message %s {
  int64 id = 1;
  // TODO: 添加字段
}

message Create%sRequest {
  // TODO: 添加字段
}

message Create%sResponse {
  int64 id = 1;
  string message = 2;
}

message Get%sRequest {
  int64 id = 1;
}

message Get%sResponse {
  int64 id = 1;
  // TODO: 添加字段
  string created_at = 2;
  string updated_at = 3;
}

message Update%sRequest {
  int64 id = 1;
  // TODO: 添加字段
}

message Update%sResponse {
  bool success = 1;
  string message = 2;
}

message Delete%sRequest {
  int64 id = 1;
}

message Delete%sResponse {
  bool success = 1;
  string message = 2;
}

message List%sRequest {
  int64 page = 1;
  int64 limit = 2;
}

message List%sResponse {
  repeated %s items = 1;
  int64 total = 2;
  int64 page = 3;
  int64 limit = 4;
}
`,
		strings.ToLower(config.ServiceName),
		config.ModulePath,
		config.ServiceName,
		config.ServiceName, config.ServiceName,
		config.ServiceName, config.ServiceName,
		config.ServiceName, config.ServiceName,
		config.ServiceName, config.ServiceName,
		config.ServiceName, config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
		config.ServiceName,
	)

	protoFile := filepath.Join(serviceDir, "api/proto", strings.ToLower(config.ServiceName)+".proto")
	return os.WriteFile(protoFile, []byte(content), 0644)
}

// initGit 初始化 Git
func initGit(serviceDir, gitRepo string) error {
	cmds := [][]string{
		{"git", "init"},
		{"git", "add", "."},
		{"git", "commit", "-m", "Initial commit from uyou scaffold"},
	}

	for _, cmd := range cmds {
		c := exec.Command(cmd[0], cmd[1:]...)
		c.Dir = serviceDir
		if err := c.Run(); err != nil {
			return err
		}
	}

	return nil
}
