# ===========================
# PHP 8.2 FPM 优化镜像 (512MB 专用 | 保留 mysqli/pdo_mysql | 修复 OPcache 重复加载)
# 作者：AI助手 | 日期：2026-03-12
# ===========================

# ---------- 阶段1：编译 Redis 扩展 ----------
FROM php:8.2-fpm-alpine AS builder

RUN apk add --no-cache $PHPIZE_DEPS hiredis-dev && \
    pecl install redis-6.3.0 && \
    docker-php-ext-enable redis


# ---------- 阶段2：生产运行时（全优化） ----------
FROM php:8.2-fpm-alpine

# === 1. 时区固化 ===
ENV TZ=Asia/Shanghai \
    PHP_INI_DIR=/usr/local/etc/php
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# === 2. 安装 MySQL 客户端库 ===
RUN apk add --no-cache mariadb-connector-c

# === 3. 复制 Redis 扩展 ===
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20220829/redis.so \
                     /usr/local/lib/php/extensions/no-debug-non-zts-20220829/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini \
                     /usr/local/etc/php/conf.d/

# === 4. 【精准移除】仅删除 sodium + sqlite（mysqli/pdo_mysql 完整保留！）===
RUN rm -f /usr/local/etc/php/conf.d/*sodium*.ini \
           /usr/local/etc/php/conf.d/*sqlite*.ini 2>/dev/null || true

# === 5. OPcache 配置（关键修复：移除 zend_extension 行！）===
# Alpine 镜像中 OPcache 是内置 Zend 扩展，无需 zend_extension
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

# === 6. PHP 全局参数（含 mysqli 优化）===
RUN cat > ${PHP_INI_DIR}/conf.d/99-prod.ini <<'EOF'
memory_limit = 128M
upload_max_filesize = 20M
post_max_size = 24M
max_execution_time = 60
date.timezone = Asia/Shanghai
expose_php = Off
log_errors = On
display_errors = Off
disable_functions = exec,passthru,shell_exec,system,proc_open,popen
mysqli.reconnect = Off
realpath_cache_size = 1024K
realpath_cache_ttl = 60
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

# === 8. 【修复验证】独立检查各模块（避免 OPcache 重复加载报错）===
RUN php -m | grep -q "mysqli" && \
    echo "✅ mysqli 启用" && \
    php -m | grep -q "pdo_mysql" && \
    echo "✅ pdo_mysql 启用" && \
    php -m | grep -q "redis" && \
    echo "✅ redis 启用" && \
    php -m | grep -q "Zend OPcache" && \
    echo "✅ OPcache 启用" && \
    ! (php -m | grep -qE "sodium|sqlite") && \
    echo "✅ sodium/sqlite 已移除" && \
    echo "🎉 镜像构建验证全部通过！"

# === 9. 基础环境 ===
WORKDIR /app
EXPOSE 9000
USER www-data
CMD ["php-fpm"]
