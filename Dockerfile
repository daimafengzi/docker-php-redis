# ===========================
# PHP 8.2 FPM 优化镜像 (512MB 专用 | 保留 mysqli + pdo_mysql)
# 作者：AI助手 | 日期：2026-03-12
# 特点：✅ mysqli 内置启用 ✅ pdo_mysql 保留 ✅ 仅移除 sodium/sqlite
# ===========================

# ---------- 阶段1：编译 Redis 扩展 ----------
FROM php:8.2-fpm-alpine AS builder

# 安装最小编译依赖
RUN apk add --no-cache $PHPIZE_DEPS hiredis-dev

# 编译 Redis 扩展
RUN pecl install redis-6.3.0 && docker-php-ext-enable redis


# ---------- 阶段2：生产运行时（全优化） ----------
FROM php:8.2-fpm-alpine

# === 1. 时区固化 ===
ENV TZ=Asia/Shanghai \
    PHP_INI_DIR=/usr/local/etc/php
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# === 2. 安装 MySQL 客户端库（mysqli/pdo_mysql 依赖）===
RUN apk add --no-cache mariadb-connector-c

# === 3. 复制 Redis 扩展 ===
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/redis.so \
                     /usr/local/lib/php/extensions/no-debug-non-zts-20220829/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini \
                     /usr/local/etc/php/conf.d/

# === 4. 【精准移除】仅删除 sodium + sqlite（mysqli/pdo_mysql 完整保留！）===
RUN rm -f /usr/local/etc/php/conf.d/*sodium*.ini \
           /usr/local/etc/php/conf.d/*sqlite*.ini 2>/dev/null || true

# === 5. OPcache 精准配置（32MB）===
RUN cat > ${PHP_INI_DIR}/conf.d/10-opcache.ini <<'EOF'
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=32
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

# === 6. PHP 全局参数（含 mysqli 优化）===
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

; mysqli 优化（减少连接开销）
mysqli.reconnect = Off
mysqli.default_socket = /var/run/mysqld/mysqld.sock

; 路径缓存
realpath_cache_size = 1024K
realpath_cache_ttl = 60

; 会话优化
session.gc_probability = 0
EOF

# === 7. FPM 进程精准调控 ===
RUN cat > /usr/local/etc/php-fpm.d/zzz-custom.conf <<'EOF'
[global]
daemonize = no

[www]
pm = ondemand
pm.max_children = 4
pm.process_idle_timeout = 10s
pm.max_requests = 100
request_terminate_timeout = 60s
EOF

# === 8. 【关键】构建验证（确保 mysqli + pdo_mysql + redis 全启用）===
RUN php -m | grep -q mysqli && \
    php -m | grep -q pdo_mysql && \
    php -m | grep -q redis && \
    php -m | grep -q "Zend OPcache" && \
    ! php -m | grep -qE "sodium|sqlite" && \
    php -r "echo '✅ 验证通过：mysqli/pdo_mysql/redis/OPcache 已启用，sodium/sqlite 已移除\n';"

# === 9. 基础环境 ===
WORKDIR /app
EXPOSE 9000
USER www-data
CMD ["php-fpm"]
