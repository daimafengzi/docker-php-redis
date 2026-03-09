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

# 3. 【关键策略】创建一个临时目录，把所有需要的 .so 文件集中到这里
# 这样不管它们原本散落在哪里，我们都能确切知道去哪里拿
RUN mkdir -p /tmp/php-extensions \
    && cp $(php -r "echo ini_get('extension_dir');")/redis.so /tmp/php-extensions/ \
    && cp $(php -r "echo ini_get('extension_dir');")/pdo_mysql.so /tmp/php-extensions/ \
    && echo "Files copied to /tmp/php-extensions:" && ls -l /tmp/php-extensions/

# 4. 同样备份 ini 文件
RUN mkdir -p /tmp/php-ini \
    && cp /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /tmp/php-ini/ \
    && cp /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /tmp/php-ini/

# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 1. 安装运行时依赖
RUN apk add --no-cache mariadb-connector-c

# 2. 获取扩展目录
RUN PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');") && \
    mkdir -p "$PHP_EXT_DIR"

# 3. 【绝对可靠】从 Builder 的临时目录直接复制文件
# 不再依赖通配符匹配子目录，直接从 /tmp/php-extensions 拿
COPY --from=builder /tmp/php-extensions/redis.so "$PHP_EXT_DIR/redis.so"
COPY --from=builder /tmp/php-extensions/pdo_mysql.so "$PHP_EXT_DIR/pdo_mysql.so"

# 4. 复制配置文件
COPY --from=builder /tmp/php-ini/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /tmp/php-ini/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# 5. 最终验证 (如果这里还失败，说明上面复制真的没成功，会直接阻断)
RUN set -ex; \
    echo "Checking extensions..."; \
    php -m | grep -q redis || (echo "❌ FATAL: Redis missing" && exit 1); \
    php -m | grep -q pdo_mysql || (echo "❌ FATAL: PDO MySQL missing" && exit 1); \
    php -r "if (!defined('PDO::MYSQL_ATTR_INIT_COMMAND')) { echo '❌ FATAL: Constant missing'; exit(1); }"; \
    echo "✅ SUCCESS: Image is valid."

WORKDIR /app
CMD ["php-fpm"]
