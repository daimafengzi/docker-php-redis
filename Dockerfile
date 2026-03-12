# ===========================
# 阶段 1: Builder (编译环境)
# ===========================
FROM php:8.2-fpm-alpine AS builder

# 仅安装编译必需依赖
RUN apk add --no-cache $PHPIZE_DEPS hiredis-dev mariadb-dev linux-headers

# 安装必要扩展
RUN pecl install redis-6.3.0 && docker-php-ext-enable redis
RUN docker-php-ext-install pdo_mysql

# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 1. 安装运行时依赖（仅 mariadb-connector-c）
RUN apk add --no-cache mariadb-connector-c

# 2. 复制扩展文件（路径硬编码，Alpine PHP 8.2 固定）
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-*.ini /usr/local/etc/php/conf.d/

# 3. 【小内存核心修改】OPcache 配置（仅改 3 行！）
RUN cat > /usr/local/etc/php/conf.d/10-opcache.ini <<'EOF'
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=64        ; 原 256 → 改为 64 (小内存关键)
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.validate_timestamps=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.jit_buffer_size=0            ; 原 100M → 改为 0 (禁用 JIT)
opcache.jit=disable                  ; 原 1235 → 改为 disable
opcache.enable_cli=0
EOF

# 4. 【保留】扩展验证（您的原逻辑）
RUN php -m | grep -q redis || (echo "ERROR: Redis not loaded" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL not loaded" && exit 1)
RUN php -m | grep -q "Zend OPcache" || (echo "ERROR: OPcache not loaded" && exit 1)
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: Constant missing');"

WORKDIR /app
EXPOSE 9000
CMD ["php-fpm"]
