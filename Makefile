.PHONY: proto clean build run stop

# 生成 Proto 文件
proto:
	@echo "Generating protobuf files..."
	@mkdir -p services/user/proto services/order/proto services/feed/proto
	protoc --go_out=services/user/proto --go_opt=paths=source_relative \
		--go-grpc_out=services/user/proto --go-grpc_opt=paths=source_relative \
		proto/user.proto
	protoc --go_out=services/order/proto --go_opt=paths=source_relative \
		--go-grpc_out=services/order/proto --go-grpc_opt=paths=source_relative \
		proto/order.proto
	protoc --go_out=services/feed/proto --go_opt=paths=source_relative \
		--go-grpc_out=services/feed/proto --go-grpc_opt=paths=source_relative \
		proto/feed.proto
	@echo "Protobuf files generated successfully!"

# 构建所有服务
build:
	@echo "Building services..."
	cd services/user && go mod tidy && go build -o user-service
	cd services/order && go mod tidy && go build -o order-service
	cd services/feed && go mod tidy && go build -o feed-service
	@echo "All services built successfully!"

# 启动所有服务
run:
	@echo "Starting all services with Docker Compose..."
	docker-compose up -d
	@echo "All services started!"
	@echo "APISIX Dashboard: http://localhost:9000"
	@echo "APISIX Gateway: http://localhost:9080"

# 停止所有服务
stop:
	@echo "Stopping all services..."
	docker-compose down
	@echo "All services stopped!"

# 清理生成的文件
clean:
	@echo "Cleaning generated files..."
	rm -rf services/*/proto/*.go
	rm -rf services/*/user-service services/*/order-service services/*/feed-service
	@echo "Cleanup complete!"

# 查看日志
logs:
	docker-compose logs -f

# 重启服务
restart: stop run
