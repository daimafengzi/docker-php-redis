FROM php:8.2-fpm-alpine AS builder

# 1. 安装所有必要的编译依赖
# 注意：增加了 mariadb-dev (用于 pdo_mysql)
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
    # 2. 编译并启用 pdo_mysql
    && docker-php-ext-install pdo_mysql

# --- 以下保持你的原有逻辑，用于复制 redis 扩展 ---
FROM php:8.2-fpm-alpine

# 安装运行时依赖 (如果 pdo_mysql 需要动态库，最好在这里也装上，虽然通常编译进so了)
# 为了稳妥，建议在生产镜像也装上 mariadb-client-libs (可选，视具体情况)
RUN apk add --no-cache mariadb-client-libs

# 获取 PHP 扩展目录
RUN PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');") && \
    EXT_VERSION=$(basename $PHP_EXT_DIR) && \
    mkdir -p /usr/local/lib/php/extensions/$EXT_VERSION

# 从 builder 复制 redis.so
COPY --from=builder /usr/local/lib/php/extensions/*/redis.so /tmp/redis.so

# 移动 redis.so 到正确位置
RUN PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');") && \
    cp /tmp/redis.so $PHP_EXT_DIR/redis.so && \
    rm /tmp/redis.so

# 复制 redis 配置文件
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/

# 【新增】从 builder 复制 pdo_mysql 配置文件
# docker-php-ext-install 会自动生成这个文件
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# 验证
RUN php -m | grep -q redis || (echo "❌ Redis extension load failed" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "❌ PDO MySQL extension load failed" && exit 1)

WORKDIR /app
CMD ["php-fpm"]
