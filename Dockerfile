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

# 1. 安装 Redis
RUN pecl install redis \
    && docker-php-ext-enable redis

# 2. 安装 PDO MySQL
RUN docker-php-ext-install pdo_mysql

# 3. 验证 Builder 阶段文件是否存在 (调试用)
RUN ls -l /usr/local/lib/php/extensions/no-debug-non-zts-20220829/ | grep -E "(redis|pdo_mysql)"

# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 1. 安装运行时依赖
RUN apk add --no-cache mariadb-connector-c

# 2. 【硬编码路径】Alpine PHP 8.2 固定路径
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829

# 3. 创建目录 (以防万一)
RUN mkdir -p ${PHP_EXT_DIR}

# 4. 【核心修复】直接复制 .so 文件
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so

# 5. 复制配置文件
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# >>>>>>>>>>> 新增：启用 OPcache <<<<<<<<<<<
RUN docker-php-ext-enable opcache

# 6. 简单验证 (不再使用复杂的 set -ex 多行脚本，减少解析错误)
RUN php -m | grep -q redis || (echo "ERROR: Redis not loaded" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL not loaded" && exit 1)
RUN php -m | grep -q "Zend OPcache" || (echo "ERROR: OPcache not loaded" && exit 1)
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: Constant missing');"

WORKDIR /app
CMD ["php-fpm"]
