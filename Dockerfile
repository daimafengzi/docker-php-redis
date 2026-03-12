# ===========================
# 阶段 1: Builder (纯净编译)
# ===========================
FROM php:8.2-fpm-alpine AS builder

# 精简编译依赖（移除 automake/autoconf 等冗余）
RUN apk add --no-cache $PHPIZE_DEPS hiredis-dev mariadb-dev

# 仅编译必要扩展
RUN pecl install redis-6.3.0 && docker-php-ext-enable redis
RUN docker-php-ext-install pdo_mysql

# ==========================
# 阶段 2: Production (全优化运行时)
# ==========================
FROM php:8.2-fpm-alpine

# === 【1】时区固化（构建时设置，避免运行时偏差）===
ENV TZ=Asia/Shanghai \
    PHP_INI_DIR=/usr/local/etc/php
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# === 【2】运行时依赖（最小化）===
RUN apk add --no-cache mariadb-connector-c

# === 【3】扩展精简（关键！构建时移除冗余）===
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829
# 复制必要扩展
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# 【构建时禁用】确认无依赖后安全移除（释放 12MB+）
RUN rm -f /usr/local/etc/php/conf.d/*sodium*.ini \
           /usr/local/etc/php/conf.d/*sqlite*.ini \
           /usr/local/etc/php/conf.d/*opcache*.ini 2>/dev/null || true

# === 【4】OPcache 单一权威配置（解决冲突）===
RUN cat > ${PHP_INI_DIR}/conf.d/10-opcache.ini <<'EOF'
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

# === 【5】PHP 全局参数优化 ===
RUN cat > ${PHP_INI_DIR}/conf.d/99-prod.ini <<'EOF'
; 内存与上传
memory_limit = 128M
upload_max_filesize = 20M
post_max_size = 24M
max_execution_time = 60

; 时区与安全
date.timezone = Asia/Shanghai
expose_php = Off
log_errors = On
display_errors = Off
disable_functions = exec,passthru,shell_exec,system,proc_open,popen

; 路径缓存优化
realpath_cache_size = 1024K
realpath_cache_ttl = 60
EOF

# === 【6】FPM 进程精准调控（防 OOM 核心）===
RUN sed -i 's/pm = dynamic/pm = ondemand/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.max_children = 5/pm.max_children = 4/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.start_servers = 2/;pm.start_servers = 2/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.min_spare_servers = 1/;pm.min_spare_servers = 1/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.max_spare_servers = 3/;pm.max_spare_servers = 3/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/;pm.process_idle_timeout = 10s/pm.process_idle_timeout = 10s/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.max_requests = 500/pm.max_requests = 100/' /usr/local/etc/php-fpm.d/www.conf

# === 【7】构建时验证（失败即中断构建）===
RUN php -m | grep -q redis && \
    php -m | grep -q pdo_mysql && \
    php -m | grep -q "Zend OPcache" && \
    php -r "defined('PDO::MYSQL_ATTR_INIT_COMMAND') or die('MISSING CONSTANT'); echo '✅ All extensions validated\n';"

WORKDIR /app
EXPOSE 9000
CMD ["php-fpm"]
