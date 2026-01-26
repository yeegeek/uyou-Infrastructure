.PHONY: proto proto-update update-apisix-merge generate-route validate-config cleanup-old-routes clean build run stop restart logs new-service help

# 生成新的微服务
new-service:
	@echo "🚀 生成新的微服务..."
	@cd service-scaffold && go run generator.go
	@echo ""
	@echo "✅ 服务生成成功！"
	@echo ""
	@echo "📝 后续步骤："
	@echo "   1. 进入新服务目录"
	@echo "   2. 编辑 api/proto/*.proto 定义 API"
	@echo "   3. 运行 'make proto' 生成代码"
	@echo "   4. 实现业务逻辑"
	@echo "   5. 构建和运行服务"

# 帮助信息
help:
	@echo "可用命令:"
	@echo ""
	@echo "微服务生成:"
	@echo "  make new-service         - 生成新的微服务（交互式）"
	@echo ""
	@echo "APISIX 配置管理:"
	@echo "  make update-apisix-merge - 合并并更新 APISIX 配置（从 apisix/config/routes/ 读取）"
	@echo "  make validate-config     - 验证 APISIX 配置"
	@echo "  make cleanup-old-routes  - 清理旧路由（没有 jwt-auth 的路由）"
	@echo ""
	@echo "本地开发（如果 services/ 目录有微服务代码）:"
	@echo "  make proto               - 生成所有微服务的 Proto 代码文件"
	@echo "  make generate-route      - 从 proto 生成所有服务的路由配置（自动遍历）"
	@echo "  make generate-route SERVICE=<name> - 生成指定服务的路由配置"
	@echo "  make build               - 构建所有微服务"
	@echo ""
	@echo "服务管理:"
	@echo "  make run                 - 启动所有服务（Docker Compose）"
	@echo "  make stop                - 停止所有服务"
	@echo "  make restart             - 重启服务"
	@echo "  make logs                - 查看日志"
	@echo "  make clean               - 清理生成的文件"
	@echo ""
	@echo "环境变量:"
	@echo "  APISIX_ENV=dev           - 设置环境（dev/staging/prod）"
	@echo "  APISIX_ADMIN_URL         - APISIX Admin API 地址"
	@echo "  APISIX_ADMIN_KEY         - APISIX Admin API 密钥"
	@echo ""
	@echo "说明:"
	@echo "  - services/ 目录用于本地开发，不提交到 Git"
	@echo "  - 路由配置通过各微服务仓库的 apisix/routes.yaml 文件提供"
	@echo "  - 使用 make update-apisix-merge 合并并部署所有路由配置"

# 生成 Proto 文件（自动遍历本地 services/ 目录中的微服务）
# 注意：这仅用于本地开发，微服务仓库有自己的 make proto 命令
proto:
	@echo "生成 Proto 代码文件（本地开发模式）..."
	@if [ ! -d "services" ] || [ -z "$$(ls -A services 2>/dev/null)" ]; then \
		echo "⚠ services/ 目录为空或不存在"; \
		echo "提示: 如果需要本地开发，请克隆微服务仓库到 services/ 目录"; \
		echo "  例如: git clone https://github.com/your-org/uyou-user-service.git services/user-service"; \
		exit 0; \
	fi
	@failed=0; \
	for service_dir in services/*/; do \
		service_name=$$(basename "$$service_dir"); \
		proto_dir="$$service_dir/proto"; \
		if [ -d "$$proto_dir" ]; then \
			echo "处理微服务: $$service_name"; \
			proto_files=$$(find "$$proto_dir" -maxdepth 1 -name "*.proto" 2>/dev/null | sort); \
			if [ -n "$$proto_files" ]; then \
				service_failed=0; \
				for proto_file in $$proto_files; do \
					proto_name=$$(basename "$$proto_file" .proto); \
					echo "  生成: $$proto_name.proto"; \
					cd "$$proto_dir" && \
					if protoc --go_out=. --go_opt=paths=source_relative \
						--go-grpc_out=. --go-grpc_opt=paths=source_relative \
						"$$(basename "$$proto_file")" > /dev/null 2>&1; then \
						echo "    ✓ 成功"; \
					else \
						echo "    ✗ 失败"; \
						service_failed=1; \
						failed=1; \
					fi; \
					cd - > /dev/null; \
				done; \
				if [ $$service_failed -eq 0 ]; then \
					echo "  ✓ $$service_name 完成"; \
				else \
					echo "  ✗ $$service_name 有错误"; \
				fi; \
			else \
				echo "  ⚠ $$service_name: 未找到 .proto 文件"; \
			fi; \
		else \
			echo "  ⚠ $$service_name: 未找到 proto/ 目录，跳过"; \
		fi; \
	done; \
	if [ $$failed -eq 1 ]; then \
		echo ""; \
		echo "错误: 部分 protobuf 文件生成失败"; \
		echo "请确保已安装 protoc-gen-go 和 protoc-gen-go-grpc:"; \
		echo "  go install google.golang.org/protobuf/cmd/protoc-gen-go@latest"; \
		echo "  go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest"; \
		exit 1; \
	else \
		echo "Protobuf files generated successfully!"; \
	fi

# 更新 APISIX 路由配置（推荐方式：合并多个配置文件）
# 从 apisix/config/routes/ 目录读取所有微服务的路由配置并合并部署
update-apisix-merge:
	@echo "合并并更新 APISIX 配置（多服务方式）..."
	@echo "从 apisix/config/routes/ 读取路由配置..."
	@./scripts/merge-apisix-configs.sh
	@echo "APISIX configuration updated!"

# 从 proto 文件生成路由配置（本地开发用）
# 如果指定了 SERVICE，只生成该服务的路由配置
# 如果没有指定 SERVICE，自动遍历 services/ 目录下的所有服务
generate-route:
	@if [ -n "$(SERVICE)" ]; then \
		echo "从 proto 文件生成路由配置: $(SERVICE)"; \
		if [ ! -f "services/$(SERVICE)/proto/$(SERVICE).proto" ]; then \
			echo "错误: 找不到 services/$(SERVICE)/proto/$(SERVICE).proto"; \
			echo "提示: 请先克隆微服务仓库到 services/ 目录"; \
			exit 1; \
		fi; \
		./scripts/generate-route-config.sh $(SERVICE) services/$(SERVICE)/proto/$(SERVICE).proto; \
	else \
		echo "从 proto 文件生成路由配置（自动遍历所有服务）..."; \
		if [ ! -d "services" ] || [ -z "$$(ls -A services 2>/dev/null)" ]; then \
			echo "⚠ services/ 目录为空或不存在"; \
			echo "提示: 如果需要生成路由配置，请先克隆微服务仓库到 services/ 目录"; \
			echo "  例如: git clone https://github.com/your-org/uyou-user-service.git services/user-service"; \
			echo ""; \
			echo "或者指定单个服务: make generate-route SERVICE=user"; \
			exit 0; \
		fi; \
		failed=0; \
		generated=0; \
		for service_dir in services/*/; do \
			service_name=$$(basename "$$service_dir"); \
			proto_file="$$service_dir/proto/$$service_name.proto"; \
			if [ -f "$$proto_file" ]; then \
				echo "处理微服务: $$service_name"; \
				if ./scripts/generate-route-config.sh $$service_name "$$proto_file"; then \
					echo "  ✓ $$service_name 路由配置已生成"; \
					generated=$$((generated + 1)); \
				else \
					echo "  ✗ $$service_name 路由配置生成失败"; \
					failed=$$((failed + 1)); \
				fi; \
			else \
				echo "  ⚠ $$service_name: 未找到 proto/$$service_name.proto，跳过"; \
			fi; \
		done; \
		echo ""; \
		if [ $$generated -gt 0 ]; then \
			echo "✓ 成功生成 $$generated 个服务的路由配置"; \
		fi; \
		if [ $$failed -gt 0 ]; then \
			echo "✗ $$failed 个服务的路由配置生成失败"; \
			exit 1; \
		fi; \
		if [ $$generated -eq 0 ] && [ $$failed -eq 0 ]; then \
			echo "⚠ 没有找到任何 proto 文件"; \
		fi; \
	fi

# 验证 APISIX 配置
validate-config:
	@echo "验证 APISIX 配置..."
	@./scripts/validate-config.sh

# 清理旧路由配置（没有 jwt-auth 插件的路由）
cleanup-old-routes:
	@echo "清理旧路由配置..."
	@./scripts/cleanup-old-routes.sh

# 构建所有服务（自动遍历本地 services/ 目录中的微服务）
build:
	@echo "构建服务（本地开发模式）..."
	@if [ ! -d "services" ] || [ -z "$$(ls -A services 2>/dev/null)" ]; then \
		echo "⚠ services/ 目录为空或不存在"; \
		echo "提示: 微服务通常在各自的仓库中构建"; \
		exit 0; \
	fi
	@for service_dir in services/*/; do \
		service_name=$$(basename "$$service_dir"); \
		if [ -f "$$service_dir/go.mod" ]; then \
			echo "构建微服务: $$service_name"; \
			cd "$$service_dir" && go mod tidy && go build -o "$$service_name-service" . || exit 1; \
			cd - > /dev/null; \
			echo "  ✓ $$service_name 构建完成"; \
		else \
			echo "  ⚠ $$service_name: 未找到 go.mod，跳过"; \
		fi; \
	done
	@echo "All services built successfully!"

# 启动所有服务
run:
	@echo "启动所有服务（Docker Compose）..."
	@docker compose up -d
	@echo "所有服务已启动！"
	@echo "APISIX Gateway: http://localhost:9080"
	@echo "APISIX Admin API: http://localhost:9180"
	@echo ""
	@echo "提示: 使用 'make update-apisix-merge' 初始化路由配置"

# 停止所有服务
stop:
	@echo "停止所有服务..."
	@docker compose down
	@echo "所有服务已停止！"

# 清理生成的文件（自动遍历本地 services/ 目录中的微服务）
clean:
	@echo "清理生成的文件..."
	@if [ -d "services" ]; then \
		for service_dir in services/*/; do \
			service_name=$$(basename "$$service_dir"); \
			echo "清理: $$service_name"; \
			rm -f "$$service_dir/proto"/*.go 2>/dev/null; \
			rm -f "$$service_dir/$$service_name-service" 2>/dev/null; \
		done; \
	fi
	@echo "清理完成！"

# 查看日志
logs:
	@docker compose logs -f

# 重启服务
restart: stop run
