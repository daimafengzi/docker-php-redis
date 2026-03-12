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

# 2. 安装 PDO MySQL（会生成 .so）
RUN docker-php-ext-install pdo_mysql

# 注意：不再安装 mysqli，因为它不生成 .so，且无需在 builder 处理


# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 1. 安装运行时依赖
RUN apk add --no-cache mariadb-connector-c

# 2. 【关键】启用 mysqli（核心扩展，无需 .so，直接启用）
#    docker-php-ext-install 对 core extensions 实际是创建一个空 .ini 启用它
RUN docker-php-ext-install mysqli

# 3. 硬编码路径（只为 redis 和 pdo_mysql 用）
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829

# 4. 创建目录
RUN mkdir -p ${PHP_EXT_DIR}

# 5. 只复制需要 .so 的扩展（redis, pdo_mysql）
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so
# ← 不再复制 mysqli.so（它不存在！）

# 6. 复制 .ini 文件（只针对 redis 和 pdo_mysql）
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/
# mysqli 会由 docker-php-ext-install 自动生成 ini 或内建启用

# 7. 启用 OPcache
RUN docker-php-ext-enable opcache \
    && { \
        echo 'opcache.enable=1'; \
        echo 'opcache.memory_consumption=256'; \
        echo 'opcache.interned_strings_buffer=16'; \
        echo 'opcache.max_accelerated_files=20000'; \
        echo 'opcache.revalidate_freq=0'; \
        echo 'opcache.validate_timestamps=0'; \
        echo 'opcache.fast_shutdown=1'; \
    } > /usr/local/etc/php/conf.d/10-opcache.ini

# 8. 验证所有扩展
RUN php -m | grep -q redis || (echo "ERROR: Redis not loaded" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL not loaded" && exit 1)
RUN php -m | grep -q mysqli || (echo "ERROR: MySQLi not loaded" && exit 1)
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: Constant missing');"
RUN php -r "function_exists('mysqli_connect') or die('ERROR: mysqli_connect missing');"

WORKDIR /app
CMD ["php-fpm"]
