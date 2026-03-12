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

# 调试：验证扩展是否生成（可选，构建成功即可删）
# RUN ls -l /usr/local/lib/php/extensions/no-debug-non-zts-20220829/ | grep -E "(redis|pdo_mysql)"


# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 安装运行时依赖（Redis 不需要额外 lib，但 MySQL 需要）
RUN apk add --no-cache mariadb-connector-c

# === 动态获取扩展目录（比硬编码更健壮）===
ENV PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');")

# === 启用 OPcache 并写入生产级配置 ===
# 注意：docker-php-ext-enable 只生成 .ini，不设参数
RUN docker-php-ext-enable opcache \
    && { \
        echo 'opcache.enable=1'; \
        echo 'opcache.memory_consumption=256'; \
        echo 'opcache.interned_strings_buffer=16'; \
        echo 'opcache.max_accelerated_files=20000'; \
        echo 'opcache.revalidate_freq=0'; \
        echo 'opcache.validate_timestamps=0'; \
        echo 'opcache.fast_shutdown=1'; \
        echo 'opcache.jit_buffer_size=100M'; \
        echo 'opcache.jit=1235'; \
    } > /usr/local/etc/php/conf.d/10-opcache.ini

# === 复制预编译的扩展文件 ===
# 目录已存在（来自基础镜像），无需 mkdir -p
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so

# === 复制扩展的 .ini 配置文件 ===
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# === 验证所有扩展加载成功 ===
RUN php -m | grep -q redis || (echo "ERROR: Redis extension not loaded" && exit 1) \
    && php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL extension not loaded" && exit 1) \
    && php -m | grep -q "Zend OPcache" || (echo "ERROR: OPcache not loaded" && exit 1) \
    && php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: PDO MySQL constant missing');"

# 设置工作目录
WORKDIR /app

# 启动命令
CMD ["php-fpm"]
