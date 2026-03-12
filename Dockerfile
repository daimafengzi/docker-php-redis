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

# 安装 Redis 扩展
RUN pecl install redis \
    && docker-php-ext-enable redis

# 安装 PDO MySQL 扩展
RUN docker-php-ext-install pdo_mysql


# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 安装运行时依赖
RUN apk add --no-cache mariadb-connector-c

# 🔑 硬编码 PHP 8.2 扩展目录（Alpine 固定路径）
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829

# 启用 OPcache 并写入生产配置
RUN docker-php-ext-enable opcache \
    && { \
        echo 'opcache.enable=1'; \
        echo 'opcache.memory_consumption=256'; \
        echo 'opcache.max_accelerated_files=20000'; \
        echo 'opcache.revalidate_freq=0'; \
        echo 'opcache.validate_timestamps=0'; \
        echo 'opcache.fast_shutdown=1'; \
    } > /usr/local/etc/php/conf.d/10-opcache.ini

# 复制预编译的扩展文件（.so）
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so

# 复制扩展的 .ini 配置
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# 验证所有扩展加载成功（单行合并，避免多层）
RUN php -m | grep -q redis \
    && php -m | grep -q pdo_mysql \
    && php -m | grep -q "Zend OPcache" \
    && php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('Missing PDO MySQL constant');"

WORKDIR /app
CMD ["php-fpm"]
