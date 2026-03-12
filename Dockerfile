# ===========================
# PHP 8.2 FPM 优化镜像 (512MB 专用 | 无 USER | 自动权限修复)
# 组件：✅ Redis ✅ OPcache ✅ MySQLi ✅ PDO MySQL
# 作者：AI助手 | 日期：2026-03-12
# ===========================

# ---------- 阶段1：编译 Redis 扩展 ----------
FROM php:8.2-fpm-alpine3.19 AS builder

ARG REDIS_VERSION=6.3.0

RUN apk add --no-cache $PHPIZE_DEPS hiredis-dev && \
    pecl install redis-${REDIS_VERSION} && \
    docker-php-ext-enable redis

# ---------- 阶段2：生产运行时 ----------
FROM php:8.2-fpm-alpine3.19

# === 1. 时区 ===
ENV TZ=Asia/Shanghai PHP_INI_DIR=/usr/local/etc/php
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# === 2. 安装 MySQL 客户端库 + 启用核心扩展 ===
RUN apk add --no-cache mariadb-connector-c && \
    docker-php-ext-install mysqli pdo pdo_mysql opcache

# === 3. 复制 Redis 扩展 ===
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/redis.so \
                     /usr/local/lib/php/extensions/no-debug-non-zts-20220829/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini \
                     /usr/local/etc/php/conf.d/

# === 4. 【关键】彻底禁用不需要的扩展 ===
RUN docker-php-ext-disable sodium sqlite3 pdo_sqlite 2>/dev/null || true

# === 5. OPcache 配置 ===
RUN cat > ${PHP_INI_DIR}/conf.d/10-opcache.ini <<'EOF'
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

# === 6. PHP 全局配置 ===
RUN cat > ${PHP_INI_DIR}/conf.d/99-prod.ini <<'EOF'
memory_limit = 128M
upload_max_filesize = 20M
post_max_size = 24M
max_execution_time = 60
date.timezone = Asia/Shanghai
expose_php = Off
log_errors = On
display_errors = Off
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,dl,pcntl_exec,show_source
mysqli.reconnect = Off
realpath_cache_size = 1024K
realpath_cache_ttl = 60
session.gc_probability = 0
EOF

# === 7. FPM 配置 ===
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

# === 8. 启动脚本（权限修复）===
RUN cat > /entrypoint.sh <<'EOF'
#!/bin/sh
set -e
if [ -w /app ]; then
    chown -R www-data:www-data /app 2>/dev/null || true
fi
exec php-fpm
EOF
RUN chmod +x /entrypoint.sh

# === 9. 【可靠】构建验证（精确匹配模块名）===
RUN php -m | grep -E "^(mysqli|pdo_mysql|redis|Zend OPcache)$" | wc -l | grep -q "4" && \
    ! php -m | grep -qE "^(sodium|sqlite3|pdo_sqlite)$" && \
    echo "🎉 镜像构建验证全部通过！"

# === 10. 健康检查 ===
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD php -r 'exit(fsockopen("127.0.0.1", 9000, $errno, $errstr, 1) ? 0 : 1);'

# === 11. 最终设置 ===
WORKDIR /app
EXPOSE 9000
CMD ["/entrypoint.sh"]
