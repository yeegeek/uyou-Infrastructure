package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	pb "github.com/yeegeek/uyou-Infrastructure/services/user/proto"
)

type server struct {
	pb.UnimplementedUserServiceServer
	db    *sql.DB
	redis *redis.Client
}

var jwtSecret = []byte("your-secret-key-change-in-production")

// Register 用户注册
func (s *server) Register(ctx context.Context, req *pb.RegisterRequest) (*pb.RegisterResponse, error) {
	log.Printf("Register request: username=%s, email=%s", req.Username, req.Email)

	// 密码加密
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %v", err)
	}

	// 插入数据库
	var userID int64
	err = s.db.QueryRow(
		"INSERT INTO users (username, email, password, created_at) VALUES ($1, $2, $3, $4) RETURNING id",
		req.Username, req.Email, string(hashedPassword), time.Now(),
	).Scan(&userID)

	if err != nil {
		return nil, fmt.Errorf("failed to create user: %v", err)
	}

	return &pb.RegisterResponse{
		UserId:  userID,
		Message: "User registered successfully",
	}, nil
}

// Login 用户登录
func (s *server) Login(ctx context.Context, req *pb.LoginRequest) (*pb.LoginResponse, error) {
	log.Printf("Login request: username=%s", req.Username)

	var userID int64
	var username, hashedPassword string

	// 查询用户
	err := s.db.QueryRow(
		"SELECT id, username, password FROM users WHERE username = $1",
		req.Username,
	).Scan(&userID, &username, &hashedPassword)

	if err != nil {
		return nil, fmt.Errorf("user not found: %v", err)
	}

	// 验证密码
	err = bcrypt.CompareHashAndPassword([]byte(hashedPassword), []byte(req.Password))
	if err != nil {
		return nil, fmt.Errorf("invalid password")
	}

	// 生成 JWT Token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id":  userID,
		"username": username,
		"exp":      time.Now().Add(time.Hour * 24 * 7).Unix(), // 7天过期
	})

	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		return nil, fmt.Errorf("failed to generate token: %v", err)
	}

	// 缓存到 Redis
	cacheKey := fmt.Sprintf("user:%d", userID)
	s.redis.Set(ctx, cacheKey, username, time.Hour*24)

	return &pb.LoginResponse{
		Token:    tokenString,
		UserId:   userID,
		Username: username,
	}, nil
}

// GetUser 获取用户信息
func (s *server) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.GetUserResponse, error) {
	log.Printf("GetUser request: user_id=%d", req.UserId)

	// 先尝试从 Redis 获取
	cacheKey := fmt.Sprintf("user:%d", req.UserId)
	cachedUsername, err := s.redis.Get(ctx, cacheKey).Result()
	if err == nil {
		log.Printf("Cache hit for user_id=%d", req.UserId)
	}

	var username, email, avatar, createdAt string

	// 从数据库查询
	err = s.db.QueryRow(
		"SELECT username, email, COALESCE(avatar, ''), created_at FROM users WHERE id = $1",
		req.UserId,
	).Scan(&username, &email, &avatar, &createdAt)

	if err != nil {
		return nil, fmt.Errorf("user not found: %v", err)
	}

	// 更新缓存
	if cachedUsername == "" {
		s.redis.Set(ctx, cacheKey, username, time.Hour*24)
	}

	return &pb.GetUserResponse{
		UserId:    req.UserId,
		Username:  username,
		Email:     email,
		Avatar:    avatar,
		CreatedAt: createdAt,
	}, nil
}

// UpdateUser 更新用户信息
func (s *server) UpdateUser(ctx context.Context, req *pb.UpdateUserRequest) (*pb.UpdateUserResponse, error) {
	log.Printf("UpdateUser request: user_id=%d", req.UserId)

	_, err := s.db.Exec(
		"UPDATE users SET email = $1, avatar = $2 WHERE id = $3",
		req.Email, req.Avatar, req.UserId,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to update user: %v", err)
	}

	// 清除缓存
	cacheKey := fmt.Sprintf("user:%d", req.UserId)
	s.redis.Del(ctx, cacheKey)

	return &pb.UpdateUserResponse{
		Success: true,
		Message: "User updated successfully",
	}, nil
}

func initDB() (*sql.DB, error) {
	dbHost := getEnv("DB_HOST", "postgres")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "postgres")
	dbPassword := getEnv("DB_PASSWORD", "postgres")
	dbName := getEnv("DB_NAME", "userdb")

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

	// 创建表
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			username VARCHAR(50) UNIQUE NOT NULL,
			email VARCHAR(100) UNIQUE NOT NULL,
			password VARCHAR(255) NOT NULL,
			avatar VARCHAR(255),
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)
	`)

	return db, err
}

func initRedis() *redis.Client {
	redisHost := getEnv("REDIS_HOST", "redis")
	redisPort := getEnv("REDIS_PORT", "6379")

	client := redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", redisHost, redisPort),
		DB:   0,
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
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterUserServiceServer(s, &server{
		db:    db,
		redis: redisClient,
	})

	// 注册反射服务（用于 grpcurl 测试）
	reflection.Register(s)

	log.Println("User Service listening on :50051")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
