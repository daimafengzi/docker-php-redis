# ==========================
# 阶段 1: Builder (编译环境)
# ==========================
FROM php:8.2-fpm-alpine AS builder

# 安装编译依赖
RUN apk add --no-cache \
    $PHPIZE_DEPS \
    linux-headers \
    hiredis-dev \
    mariadb-dev \
    autoconf \
    automake

# 1. 安装 Redis 扩展
RUN pecl install redis \
    && docker-php-ext-enable redis

# 2. 安装 MySQL 相关扩展：mysqli（WordPress 必需） + pdo_mysql（可选但推荐）
RUN docker-php-ext-install pdo_mysql mysqli

# 3. 调试：确认扩展文件存在
RUN ls -l /usr/local/lib/php/extensions/no-debug-non-zts-20220829/ | grep -E "(redis|pdo_mysql|mysqli)"


# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 1. 安装运行时依赖（MySQL 客户端库 + Redis 运行时不需要额外库）
RUN apk add --no-cache mariadb-connector-c

# 2. 定义扩展目录（Alpine + PHP 8.2 固定路径）
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829

# 3. 确保目录存在
RUN mkdir -p ${PHP_EXT_DIR}

# 4. 从 builder 复制 .so 文件
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so
COPY --from=builder ${PHP_EXT_DIR}/mysqli.so ${PHP_EXT_DIR}/mysqli.so

# 5. 复制扩展配置文件（由 docker-php-ext-enable / docker-php-ext-install 自动生成）
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-mysqli.ini /usr/local/etc/php/conf.d/

# 6. 验证所有扩展是否加载成功
RUN php -m | grep -q redis || (echo "ERROR: Redis extension not loaded" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL extension not loaded" && exit 1)
RUN php -m | grep -q mysqli || (echo "ERROR: MySQLi extension not loaded" && exit 1)
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: PDO MySQL constant missing');"

# 设置工作目录
WORKDIR /app

# 启动 php-fpm
CMD ["php-fpm"]
