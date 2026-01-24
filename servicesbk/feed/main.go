package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	pb "github.com/yeegeek/uyou-Infrastructure/services/feed/proto"
)

type server struct {
	pb.UnimplementedFeedServiceServer
	mongodb *mongo.Collection
	redis   *redis.Client
}

type Feed struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	UserID    int64              `bson:"user_id"`
	Content   string             `bson:"content"`
	Images    []string           `bson:"images"`
	Location  string             `bson:"location"`
	Likes     int32              `bson:"likes"`
	Comments  int32              `bson:"comments"`
	CreatedAt time.Time          `bson:"created_at"`
}

// CreateFeed 创建动态
func (s *server) CreateFeed(ctx context.Context, req *pb.CreateFeedRequest) (*pb.CreateFeedResponse, error) {
	log.Printf("CreateFeed request: user_id=%d, content=%s", req.UserId, req.Content)

	feed := Feed{
		UserID:    req.UserId,
		Content:   req.Content,
		Images:    req.Images,
		Location:  req.Location,
		Likes:     0,
		Comments:  0,
		CreatedAt: time.Now(),
	}

	result, err := s.mongodb.InsertOne(ctx, feed)
	if err != nil {
		return nil, fmt.Errorf("failed to create feed: %v", err)
	}

	feedID := result.InsertedID.(primitive.ObjectID).Hex()

	// 缓存到 Redis
	cacheKey := fmt.Sprintf("feed:%s", feedID)
	s.redis.HSet(ctx, cacheKey, map[string]interface{}{
		"user_id":  req.UserId,
		"content":  req.Content,
		"likes":    0,
		"comments": 0,
	})
	s.redis.Expire(ctx, cacheKey, time.Hour)

	return &pb.CreateFeedResponse{
		FeedId:  feedID,
		Message: "Feed created successfully",
	}, nil
}

// GetFeed 获取动态详情
func (s *server) GetFeed(ctx context.Context, req *pb.GetFeedRequest) (*pb.GetFeedResponse, error) {
	log.Printf("GetFeed request: feed_id=%s", req.FeedId)

	// 先尝试从 Redis 获取
	cacheKey := fmt.Sprintf("feed:%s", req.FeedId)
	cachedFeed, err := s.redis.HGetAll(ctx, cacheKey).Result()
	if err == nil && len(cachedFeed) > 0 {
		log.Printf("Cache hit for feed_id=%s", req.FeedId)
	}

	objectID, err := primitive.ObjectIDFromHex(req.FeedId)
	if err != nil {
		return nil, fmt.Errorf("invalid feed_id: %v", err)
	}

	var feed Feed
	err = s.mongodb.FindOne(ctx, bson.M{"_id": objectID}).Decode(&feed)
	if err != nil {
		return nil, fmt.Errorf("feed not found: %v", err)
	}

	// 更新缓存
	if len(cachedFeed) == 0 {
		s.redis.HSet(ctx, cacheKey, map[string]interface{}{
			"user_id":  feed.UserID,
			"content":  feed.Content,
			"likes":    feed.Likes,
			"comments": feed.Comments,
		})
		s.redis.Expire(ctx, cacheKey, time.Hour)
	}

	return &pb.GetFeedResponse{
		FeedId:    req.FeedId,
		UserId:    feed.UserID,
		Content:   feed.Content,
		Images:    feed.Images,
		Location:  feed.Location,
		Likes:     feed.Likes,
		Comments:  feed.Comments,
		CreatedAt: feed.CreatedAt.Format(time.RFC3339),
	}, nil
}

// ListFeeds 获取用户动态列表
func (s *server) ListFeeds(ctx context.Context, req *pb.ListFeedsRequest) (*pb.ListFeedsResponse, error) {
	log.Printf("ListFeeds request: user_id=%d, page=%d", req.UserId, req.Page)

	skip := int64((req.Page - 1) * req.PageSize)
	limit := int64(req.PageSize)

	findOptions := options.Find()
	findOptions.SetSort(bson.D{{Key: "created_at", Value: -1}})
	findOptions.SetSkip(skip)
	findOptions.SetLimit(limit)

	cursor, err := s.mongodb.Find(ctx, bson.M{"user_id": req.UserId}, findOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to query feeds: %v", err)
	}
	defer cursor.Close(ctx)

	var feeds []*pb.GetFeedResponse
	for cursor.Next(ctx) {
		var feed Feed
		if err := cursor.Decode(&feed); err != nil {
			return nil, fmt.Errorf("failed to decode feed: %v", err)
		}

		feeds = append(feeds, &pb.GetFeedResponse{
			FeedId:    feed.ID.Hex(),
			UserId:    feed.UserID,
			Content:   feed.Content,
			Images:    feed.Images,
			Location:  feed.Location,
			Likes:     feed.Likes,
			Comments:  feed.Comments,
			CreatedAt: feed.CreatedAt.Format(time.RFC3339),
		})
	}

	// 查询总数
	total, _ := s.mongodb.CountDocuments(ctx, bson.M{"user_id": req.UserId})

	return &pb.ListFeedsResponse{
		Feeds: feeds,
		Total: int32(total),
	}, nil
}

// DeleteFeed 删除动态
func (s *server) DeleteFeed(ctx context.Context, req *pb.DeleteFeedRequest) (*pb.DeleteFeedResponse, error) {
	log.Printf("DeleteFeed request: feed_id=%s, user_id=%d", req.FeedId, req.UserId)

	objectID, err := primitive.ObjectIDFromHex(req.FeedId)
	if err != nil {
		return nil, fmt.Errorf("invalid feed_id: %v", err)
	}

	result, err := s.mongodb.DeleteOne(ctx, bson.M{
		"_id":     objectID,
		"user_id": req.UserId, // 确保只能删除自己的动态
	})

	if err != nil {
		return nil, fmt.Errorf("failed to delete feed: %v", err)
	}

	if result.DeletedCount == 0 {
		return &pb.DeleteFeedResponse{
			Success: false,
			Message: "Feed not found or unauthorized",
		}, nil
	}

	// 清除缓存
	cacheKey := fmt.Sprintf("feed:%s", req.FeedId)
	s.redis.Del(ctx, cacheKey)

	return &pb.DeleteFeedResponse{
		Success: true,
		Message: "Feed deleted successfully",
	}, nil
}

// LikeFeed 点赞动态
func (s *server) LikeFeed(ctx context.Context, req *pb.LikeFeedRequest) (*pb.LikeFeedResponse, error) {
	log.Printf("LikeFeed request: feed_id=%s, user_id=%d", req.FeedId, req.UserId)

	objectID, err := primitive.ObjectIDFromHex(req.FeedId)
	if err != nil {
		return nil, fmt.Errorf("invalid feed_id: %v", err)
	}

	// 增加点赞数
	update := bson.M{"$inc": bson.M{"likes": 1}}
	result, err := s.mongodb.UpdateOne(ctx, bson.M{"_id": objectID}, update)

	if err != nil {
		return nil, fmt.Errorf("failed to like feed: %v", err)
	}

	if result.MatchedCount == 0 {
		return &pb.LikeFeedResponse{
			Success: false,
		}, nil
	}

	// 清除缓存
	cacheKey := fmt.Sprintf("feed:%s", req.FeedId)
	s.redis.Del(ctx, cacheKey)

	// 获取最新点赞数
	var feed Feed
	s.mongodb.FindOne(ctx, bson.M{"_id": objectID}).Decode(&feed)

	return &pb.LikeFeedResponse{
		Success:    true,
		TotalLikes: feed.Likes,
	}, nil
}

func initMongoDB() (*mongo.Collection, error) {
	mongoHost := getEnv("MONGO_HOST", "mongodb")
	mongoPort := getEnv("MONGO_PORT", "27017")
	mongoUser := getEnv("MONGO_USER", "root")
	mongoPassword := getEnv("MONGO_PASSWORD", "example")
	mongoDatabase := getEnv("MONGO_DATABASE", "feeddb")

	uri := fmt.Sprintf("mongodb://%s:%s@%s:%s", mongoUser, mongoPassword, mongoHost, mongoPort)

	client, err := mongo.Connect(context.Background(), options.Client().ApplyURI(uri))
	if err != nil {
		return nil, err
	}

	// 测试连接
	if err := client.Ping(context.Background(), nil); err != nil {
		return nil, err
	}

	collection := client.Database(mongoDatabase).Collection("feeds")

	// 创建索引
	indexModel := mongo.IndexModel{
		Keys: bson.D{{Key: "user_id", Value: 1}, {Key: "created_at", Value: -1}},
	}
	collection.Indexes().CreateOne(context.Background(), indexModel)

	return collection, nil
}

func initRedis() *redis.Client {
	redisHost := getEnv("REDIS_HOST", "redis")
	redisPort := getEnv("REDIS_PORT", "6379")

	client := redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", redisHost, redisPort),
		DB:   2, // 使用不同的 DB
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
	// 初始化 MongoDB
	mongodb, err := initMongoDB()
	if err != nil {
		log.Fatalf("Failed to connect to MongoDB: %v", err)
	}

	// 初始化 Redis
	redisClient := initRedis()
	defer redisClient.Close()

	// 创建 gRPC 服务器
	lis, err := net.Listen("tcp", ":50053")
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterFeedServiceServer(s, &server{
		mongodb: mongodb,
		redis:   redisClient,
	})

	// 注册反射服务
	reflection.Register(s)

	log.Println("Feed Service listening on :50053")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
