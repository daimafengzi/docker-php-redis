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
RUN mkdir -p ${PHP_EXT_DIR}

# 3. 复制扩展 .so 文件
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/

# 4. 复制配置文件
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# >>>>>>>>>>> 关键新增：禁用不需要的扩展 <<<<<<<<<<<
RUN docker-php-ext-disable sodium pdo_sqlite sqlite3

# 5. 验证
RUN php -m | grep -q redis
RUN php -m | grep -q pdo_mysql
RUN php -m | grep -q "Zend OPcache"
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR');"

WORKDIR /app
CMD ["php-fpm"]
