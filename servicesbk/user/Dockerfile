# 构建阶段
FROM golang:1.21-alpine AS builder

WORKDIR /build

# 安装依赖
RUN apk add --no-cache git protobuf-dev

# 复制 go.mod 和 go.sum（如果存在）
COPY go.mod go.sum* ./

# 下载依赖
RUN go mod download

# 复制源代码（包括 proto 包）
COPY . .

# 构建二进制文件（使用 -mod=mod 允许自动更新依赖）
RUN CGO_ENABLED=0 GOOS=linux go build -mod=mod -a -installsuffix cgo -o user-service .

# 运行阶段
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder /build/user-service .

# 暴露端口
EXPOSE 50051

# 运行服务
CMD ["./user-service"]
