# ===========================
# 阶段 1: Builder (编译环境)
# ===========================
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

# 4. 复制扩展文件
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so

# 5. 复制扩展配置
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# ==========================
# 6. 【新增】启用并配置 OPcache（生产级）
# ==========================
RUN set -eux; \
    # 写入 OPcache 配置文件
    echo '; OPcache configuration for PHP 8.2 FPM (Production)' > /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'zend_extension=opcache.so' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo '' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.enable=1' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.memory_consumption=256' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.interned_strings_buffer=16' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.max_accelerated_files=10000' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.validate_timestamps=0' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.save_comments=1' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.fast_shutdown=1' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.jit_buffer_size=100M' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.jit=1235' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo '' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo '; Disable CLI opcache to avoid dev confusion' >> /usr/local/etc/php/conf.d/10-opcache.ini; \
    echo 'opcache.enable_cli=0' >> /usr/local/etc/php/conf.d/10-opcache.ini

# 7. 验证扩展加载（包括 OPcache）
RUN php -m | grep -q redis || (echo "ERROR: Redis not loaded" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL not loaded" && exit 1)
RUN php -m | grep -q "Zend OPcache" || (echo "ERROR: OPcache not loaded" && exit 1)
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: Constant missing');"

WORKDIR /app
CMD ["php-fpm"]
