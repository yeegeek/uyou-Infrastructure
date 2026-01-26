package main

import (
	"context"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

// ============================================
// 1. 生成 JWT Token（在用户登录时）
// ============================================

// GenerateJWTToken 生成 JWT token，用于返回给客户端
// 注意：payload 中必须包含 "key" 字段，且必须匹配 APISIX Consumer 的 key
func GenerateJWTToken(userID int64, username string) (string, error) {
	// 从环境变量获取 secret（必须与 APISIX Consumer 的 secret 一致）
	secret := os.Getenv("APISIX_JWT_SECRET")
	if secret == "" {
		secret = "your-secret-key-change-in-production"
	}

	// 创建 token claims
	claims := jwt.MapClaims{
		"key":      "user_key", // 必须！匹配 APISIX Consumer 的 key
		"user_id":  userID,     // 自定义：用户 ID
		"username": username,   // 自定义：用户名
		"exp":      time.Now().Add(7 * 24 * time.Hour).Unix(), // 7 天过期
	}

	// 创建 token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	// 签名 token（使用与 APISIX Consumer 相同的 secret）
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", err
	}

	return tokenString, nil
}

// ============================================
// 2. 从 Context 中获取用户信息（在受保护的 gRPC 方法中）
// ============================================

// UserInfo 用户信息结构
type UserInfo struct {
	UserID   int64
	Username string
}

// GetUserFromContext 从 gRPC context 中获取当前用户信息
// 方式 1：从 JWT token 中解析（推荐，包含完整用户信息）
func GetUserFromContext(ctx context.Context) (*UserInfo, error) {
	// 解析 JWT token
	claims, err := parseJWTFromContext(ctx)
	if err != nil {
		return nil, err
	}

	// 从 claims 中获取用户 ID
	userIDFloat, ok := claims["user_id"].(float64)
	if !ok {
		return nil, status.Error(codes.Internal, "invalid user_id in token")
	}
	userID := int64(userIDFloat)

	// 获取用户名
	username, _ := claims["username"].(string)

	return &UserInfo{
		UserID:   userID,
		Username: username,
	}, nil
}

// parseJWTFromContext 从 gRPC metadata 中提取并解析 JWT token
func parseJWTFromContext(ctx context.Context) (jwt.MapClaims, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "missing metadata")
	}

	// 获取 Authorization header（APISIX 会保留原始 header）
	authHeaders := md.Get("authorization")
	if len(authHeaders) == 0 {
		return nil, status.Error(codes.Unauthenticated, "missing authorization header")
	}

	// 提取 Bearer token
	authHeader := authHeaders[0]
	if !strings.HasPrefix(authHeader, "Bearer ") {
		return nil, status.Error(codes.Unauthenticated, "invalid authorization format")
	}

	tokenString := strings.TrimPrefix(authHeader, "Bearer ")

	// 解析 JWT token
	secret := os.Getenv("APISIX_JWT_SECRET")
	if secret == "" {
		secret = "your-secret-key-change-in-production"
	}

	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, status.Error(codes.Unauthenticated, "invalid token algorithm")
		}
		return []byte(secret), nil
	})

	if err != nil {
		return nil, status.Error(codes.Unauthenticated, "invalid token: "+err.Error())
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, status.Error(codes.Unauthenticated, "invalid token claims")
}

// GetUserFromContextAlternative 从 context 中获取用户信息（备选方式）
// 方式 2：从 APISIX 添加的 Header 中获取（需要查询数据库）
func GetUserFromContextAlternative(ctx context.Context) (*UserInfo, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "missing metadata")
	}

	// 获取 APISIX 自动添加的 X-Consumer-Username header
	usernames := md.Get("x-consumer-username")
	if len(usernames) == 0 {
		return nil, status.Error(codes.Unauthenticated, "missing consumer username")
	}

	// 注意：这里的 username 是 Consumer 的 username（即 "user_key"），不是实际用户名
	// 如果需要实际用户信息，需要从 JWT token 解析或查询数据库
	consumerUsername := usernames[0]

	// 如果需要实际用户信息，可以：
	// 1. 从 JWT token 解析（推荐，见 GetUserFromContext）
	// 2. 或者查询数据库：user, err := db.GetUserByUsername(consumerUsername)

	_ = consumerUsername // 避免未使用变量警告

	// 这里只是示例，实际应该从 token 解析或查询数据库
	return nil, status.Error(codes.Unimplemented, "use GetUserFromContext instead")
}

// ============================================
// 3. 使用示例：在 gRPC 服务方法中使用
// ============================================

// ExampleUsage 示例：在 gRPC 服务方法中获取用户信息
func ExampleUsage(ctx context.Context) error {
	// 获取当前用户信息
	user, err := GetUserFromContext(ctx)
	if err != nil {
		return err
	}

	// 使用用户信息进行业务处理
	_ = user.UserID
	_ = user.Username

	// 例如：验证权限
	// if user.UserID != targetUserID {
	//     return status.Error(codes.PermissionDenied, "cannot access other user's data")
	// }

	return nil
}

// ============================================
// 4. gRPC 拦截器示例（可选，用于统一处理用户认证）
// ============================================

// UserContextInterceptor 将用户信息注入到 context 中
// 这样在业务方法中可以直接使用，而不需要每次都解析
func UserContextInterceptor() grpc.UnaryServerInterceptor {
	return func(
		ctx context.Context,
		req interface{},
		info *grpc.UnaryServerInfo,
		handler grpc.UnaryHandler,
	) (interface{}, error) {
		// 尝试获取用户信息
		user, err := GetUserFromContext(ctx)
		if err == nil {
			// 将用户信息存储到 context 中（使用自定义 key）
			ctx = context.WithValue(ctx, "user_info", user)
		}
		// 注意：如果获取失败，不阻止请求继续（由业务方法决定是否需要认证）

		return handler(ctx, req)
	}
}

// GetUserFromContextWithInterceptor 从 context 中获取用户信息（使用拦截器注入的）
func GetUserFromContextWithInterceptor(ctx context.Context) (*UserInfo, error) {
	user, ok := ctx.Value("user_info").(*UserInfo)
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "user info not found in context")
	}
	return user, nil
}
