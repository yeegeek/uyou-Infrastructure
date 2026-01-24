package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	pb "github.com/yeegeek/uyou-Infrastructure/services/order/proto"
)

type server struct {
	pb.UnimplementedOrderServiceServer
	db    *sql.DB
	redis *redis.Client
}

// CreateOrder 创建订单（带事务）
func (s *server) CreateOrder(ctx context.Context, req *pb.CreateOrderRequest) (*pb.CreateOrderResponse, error) {
	log.Printf("CreateOrder request: user_id=%d, total_amount=%.2f", req.UserId, req.TotalAmount)

	// 开始事务
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %v", err)
	}
	defer tx.Rollback()

	// 生成订单号
	orderNo := fmt.Sprintf("ORD%d%d", time.Now().Unix(), req.UserId)

	// 插入订单主表
	var orderID int64
	err = tx.QueryRow(
		"INSERT INTO orders (order_no, user_id, total_amount, status, created_at) VALUES ($1, $2, $3, $4, $5) RETURNING id",
		orderNo, req.UserId, req.TotalAmount, "pending", time.Now(),
	).Scan(&orderID)

	if err != nil {
		return nil, fmt.Errorf("failed to create order: %v", err)
	}

	// 插入订单项
	for _, item := range req.Items {
		_, err = tx.Exec(
			"INSERT INTO order_items (order_id, product_id, product_name, quantity, price) VALUES ($1, $2, $3, $4, $5)",
			orderID, item.ProductId, item.ProductName, item.Quantity, item.Price,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to create order item: %v", err)
		}
	}

	// 提交事务
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %v", err)
	}

	// 缓存订单信息
	cacheKey := fmt.Sprintf("order:%d", orderID)
	orderData := map[string]interface{}{
		"order_id":     orderID,
		"order_no":     orderNo,
		"user_id":      req.UserId,
		"total_amount": req.TotalAmount,
		"status":       "pending",
	}
	orderJSON, _ := json.Marshal(orderData)
	s.redis.Set(ctx, cacheKey, orderJSON, time.Hour)

	return &pb.CreateOrderResponse{
		OrderId: orderID,
		OrderNo: orderNo,
		Message: "Order created successfully",
	}, nil
}

// GetOrder 获取订单详情
func (s *server) GetOrder(ctx context.Context, req *pb.GetOrderRequest) (*pb.GetOrderResponse, error) {
	log.Printf("GetOrder request: order_id=%d", req.OrderId)

	// 先尝试从 Redis 获取
	cacheKey := fmt.Sprintf("order:%d", req.OrderId)
	cachedOrder, err := s.redis.Get(ctx, cacheKey).Result()
	if err == nil {
		log.Printf("Cache hit for order_id=%d", req.OrderId)
	}

	var orderNo, status, createdAt string
	var userID int64
	var totalAmount float64

	// 从数据库查询订单主表
	err = s.db.QueryRow(
		"SELECT order_no, user_id, total_amount, status, created_at FROM orders WHERE id = $1",
		req.OrderId,
	).Scan(&orderNo, &userID, &totalAmount, &status, &createdAt)

	if err != nil {
		return nil, fmt.Errorf("order not found: %v", err)
	}

	// 查询订单项
	rows, err := s.db.Query(
		"SELECT product_id, product_name, quantity, price FROM order_items WHERE order_id = $1",
		req.OrderId,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to query order items: %v", err)
	}
	defer rows.Close()

	var items []*pb.OrderItem
	for rows.Next() {
		var item pb.OrderItem
		if err := rows.Scan(&item.ProductId, &item.ProductName, &item.Quantity, &item.Price); err != nil {
			return nil, fmt.Errorf("failed to scan order item: %v", err)
		}
		items = append(items, &item)
	}

	// 更新缓存
	if cachedOrder == "" {
		orderData := map[string]interface{}{
			"order_id":     req.OrderId,
			"order_no":     orderNo,
			"user_id":      userID,
			"total_amount": totalAmount,
			"status":       status,
		}
		orderJSON, _ := json.Marshal(orderData)
		s.redis.Set(ctx, cacheKey, orderJSON, time.Hour)
	}

	return &pb.GetOrderResponse{
		OrderId:     req.OrderId,
		OrderNo:     orderNo,
		UserId:      userID,
		Items:       items,
		TotalAmount: totalAmount,
		Status:      status,
		CreatedAt:   createdAt,
	}, nil
}

// ListOrders 获取用户订单列表
func (s *server) ListOrders(ctx context.Context, req *pb.ListOrdersRequest) (*pb.ListOrdersResponse, error) {
	log.Printf("ListOrders request: user_id=%d, page=%d", req.UserId, req.Page)

	offset := (req.Page - 1) * req.PageSize

	rows, err := s.db.Query(
		"SELECT id, order_no, user_id, total_amount, status, created_at FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3",
		req.UserId, req.PageSize, offset,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to query orders: %v", err)
	}
	defer rows.Close()

	var orders []*pb.GetOrderResponse
	for rows.Next() {
		var order pb.GetOrderResponse
		if err := rows.Scan(&order.OrderId, &order.OrderNo, &order.UserId, &order.TotalAmount, &order.Status, &order.CreatedAt); err != nil {
			return nil, fmt.Errorf("failed to scan order: %v", err)
		}
		orders = append(orders, &order)
	}

	// 查询总数
	var total int32
	s.db.QueryRow("SELECT COUNT(*) FROM orders WHERE user_id = $1", req.UserId).Scan(&total)

	return &pb.ListOrdersResponse{
		Orders: orders,
		Total:  total,
	}, nil
}

// UpdateOrderStatus 更新订单状态
func (s *server) UpdateOrderStatus(ctx context.Context, req *pb.UpdateOrderStatusRequest) (*pb.UpdateOrderStatusResponse, error) {
	log.Printf("UpdateOrderStatus request: order_id=%d, status=%s", req.OrderId, req.Status)

	_, err := s.db.Exec(
		"UPDATE orders SET status = $1 WHERE id = $2",
		req.Status, req.OrderId,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to update order status: %v", err)
	}

	// 清除缓存
	cacheKey := fmt.Sprintf("order:%d", req.OrderId)
	s.redis.Del(ctx, cacheKey)

	return &pb.UpdateOrderStatusResponse{
		Success: true,
		Message: "Order status updated successfully",
	}, nil
}

func initDB() (*sql.DB, error) {
	dbHost := getEnv("DB_HOST", "postgres")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "postgres")
	dbPassword := getEnv("DB_PASSWORD", "postgres")
	dbName := getEnv("DB_NAME", "orderdb")

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPassword, dbName)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, err
	}

	// 测试连接
	if err := db.Ping(); err != nil {
		return nil, err
	}

	// 创建订单主表
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS orders (
			id SERIAL PRIMARY KEY,
			order_no VARCHAR(50) UNIQUE NOT NULL,
			user_id BIGINT NOT NULL,
			total_amount DECIMAL(10, 2) NOT NULL,
			status VARCHAR(20) NOT NULL,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)
	`)
	if err != nil {
		return nil, err
	}

	// 创建订单项表
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS order_items (
			id SERIAL PRIMARY KEY,
			order_id BIGINT NOT NULL,
			product_id BIGINT NOT NULL,
			product_name VARCHAR(100) NOT NULL,
			quantity INT NOT NULL,
			price DECIMAL(10, 2) NOT NULL,
			FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
		)
	`)

	return db, err
}

func initRedis() *redis.Client {
	redisHost := getEnv("REDIS_HOST", "redis")
	redisPort := getEnv("REDIS_PORT", "6379")

	client := redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", redisHost, redisPort),
		DB:   1, // 使用不同的 DB
	})

	return client
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	// 初始化数据库
	db, err := initDB()
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// 初始化 Redis
	redisClient := initRedis()
	defer redisClient.Close()

	// 创建 gRPC 服务器
	lis, err := net.Listen("tcp", ":50052")
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterOrderServiceServer(s, &server{
		db:    db,
		redis: redisClient,
	})

	// 注册反射服务
	reflection.Register(s)

	log.Println("Order Service listening on :50052")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
