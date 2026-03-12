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

# 3. 【新增】安装 MySQLi（和 pdo_mysql 一样，使用 docker-php-ext-install）
RUN docker-php-ext-install mysqli

# 4. 验证 Builder 阶段文件是否存在 (调试用)
RUN ls -l /usr/local/lib/php/extensions/no-debug-non-zts-20220829/ | grep -E "(redis|pdo_mysql|mysqli)"


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

# 4. 【核心修复】直接复制 .so 文件（新增 mysqli.so）
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/mysqli.so ${PHP_EXT_DIR}/mysqli.so   # ← 新增这一行！

# 5. 复制配置文件（mysqli 无独立 .ini，无需复制）
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/
# 注意：mysqli 是核心扩展，启用后自动生成配置或无需额外 ini

# 6. 启用 OPcache（无 JIT）
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

# 7. 简单验证（新增 mysqli 检查）
RUN php -m | grep -q redis || (echo "ERROR: Redis not loaded" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL not loaded" && exit 1)
RUN php -m | grep -q mysqli || (echo "ERROR: MySQLi not loaded" && exit 1)   # ← 新增
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: Constant missing');"
RUN php -r "function_exists('mysqli_connect') or die('ERROR: mysqli_connect missing');"   # ← 新增

WORKDIR /app
CMD ["php-fpm"]
