#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    -- 创建 User Service 数据库
    CREATE DATABASE userdb;
    
    -- 创建 Order Service 数据库
    CREATE DATABASE orderdb;
    
    \c userdb;
    
    -- User Service 表结构
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        avatar VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    -- 插入测试数据
    INSERT INTO users (username, email, password) VALUES 
    ('testuser', 'test@example.com', '\$2a\$10\$YourHashedPasswordHere');
    
    \c orderdb;
    
    -- Order Service 表结构
    CREATE TABLE IF NOT EXISTS orders (
        id SERIAL PRIMARY KEY,
        order_no VARCHAR(50) UNIQUE NOT NULL,
        user_id BIGINT NOT NULL,
        total_amount DECIMAL(10, 2) NOT NULL,
        status VARCHAR(20) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS order_items (
        id SERIAL PRIMARY KEY,
        order_id BIGINT NOT NULL,
        product_id BIGINT NOT NULL,
        product_name VARCHAR(100) NOT NULL,
        quantity INT NOT NULL,
        price DECIMAL(10, 2) NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
    );
    
    -- 插入测试订单
    INSERT INTO orders (order_no, user_id, total_amount, status) VALUES 
    ('ORD20260122001', 1, 99.99, 'pending');
    
    INSERT INTO order_items (order_id, product_id, product_name, quantity, price) VALUES 
    (1, 1001, 'Test Product', 2, 49.99);
    
EOSQL

echo "PostgreSQL databases initialized successfully!"
