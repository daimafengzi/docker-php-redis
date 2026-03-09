FROM php:8.2-fpm-alpine AS builder

# 1. 安装编译依赖
# 注意：mariadb-dev 包含了编译 pdo_mysql 所需的头文件和库
RUN apk add --no-cache \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    make \
    g++ \
    linux-headers \
    hiredis-dev \
    mariadb-dev \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && docker-php-ext-install pdo_mysql

# --- 生产阶段 ---
FROM php:8.2-fpm-alpine

# 【修正点】删除了报错的 mariadb-client-libs 安装命令
# 通常 pdo_mysql 编译后不需要额外的运行时库，如果真需要，mariadb-connector-c 是替代包，但大多数情况不需要。
# 如果后续运行报错说找不到 libmysqlclient，再尝试安装 mariadb-connector-c
# RUN apk add --no-cache mariadb-connector-c 

# 获取 PHP 扩展目录
RUN PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');") && \
    EXT_VERSION=$(basename $PHP_EXT_DIR) && \
    mkdir -p /usr/local/lib/php/extensions/$EXT_VERSION

# 从 builder 复制 redis.so
COPY --from=builder /usr/local/lib/php/extensions/*/redis.so /tmp/redis.so

# 移动 redis.so
RUN PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');") && \
    cp /tmp/redis.so $PHP_EXT_DIR/redis.so && \
    rm /tmp/redis.so

# 复制 redis 配置文件
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/

# 【重要】从 builder 复制 pdo_mysql 配置文件
# 这一步至关重要，否则扩展不会自动加载
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# 验证
RUN php -m | grep -q redis || (echo "❌ Redis extension load failed" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "❌ PDO MySQL extension load failed" && exit 1)

WORKDIR /app
CMD ["php-fpm"]
