# ===========================
# 阶段 1: Builder (仅编译)
# ===========================
FROM php:8.2-fpm-alpine AS builder

# 最小化编译依赖
RUN apk add --no-cache $PHPIZE_DEPS hiredis-dev mariadb-dev

# 仅安装必要扩展
RUN pecl install redis-6.3.0 && docker-php-ext-enable redis
RUN docker-php-ext-install pdo_mysql

# ==========================
# 阶段 2: Production (纯净运行时)
# ==========================
FROM php:8.2-fpm-alpine

# 1. 时区修复 (关键!)
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 2. 仅安装运行时必需依赖
RUN apk add --no-cache mariadb-connector-c

# 3. 复制扩展 (硬编码路径)
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# 4. 【核心修复】单一 OPcache 配置 (解决配置冲突!)
#    删除所有其他 opcache 配置，仅保留此文件
RUN rm -f /usr/local/etc/php/conf.d/*opcache*.ini && \
    cat > /usr/local/etc/php/conf.d/10-opcache.ini <<'EOF'
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=64
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.jit_buffer_size=0
opcache.jit=disable
opcache.enable_cli=0
EOF

# 5. 【小内存关键】调整全局限制
RUN cat > /usr/local/etc/php/conf.d/99-memory-limit.ini <<'EOF'
memory_limit = 128M
upload_max_filesize = 20M
post_max_size = 24M
max_execution_time = 60
date.timezone = Asia/Shanghai
expose_php = Off
log_errors = On
display_errors = Off
EOF

# 6. 【保留】您的扩展验证
RUN php -m | grep -q redis || (echo "ERROR: Redis not loaded" && exit 1)
RUN php -m | grep -q pdo_mysql || (echo "ERROR: PDO MySQL not loaded" && exit 1)
RUN php -m | grep -q "Zend OPcache" || (echo "ERROR: OPcache not loaded" && exit 1)
RUN php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('ERROR: Constant missing');"

WORKDIR /app
EXPOSE 9000
CMD ["php-fpm"]
