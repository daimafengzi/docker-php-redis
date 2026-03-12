# 基础镜像 (Alpine 最小化)
FROM php:8.2-fpm-alpine

# 时区设置 (单行高效)
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装 Redis 扩展 (仅此扩展)
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && pecl install redis-6.3.0 \
    && docker-php-ext-enable redis \
    && apk del .build-deps \
    && rm -rf /tmp/* /var/cache/apk/*

# 【核心】OPcache 配置 (小内存优化版)
RUN mkdir -p /usr/local/etc/php/conf.d/custom && \
    cat > /usr/local/etc/php/conf.d/custom/z-opcache.ini <<'EOF'
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=64        ; 小内存主机关键: 64MB (原128/256)
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000   ; 降低文件数
opcache.validate_timestamps=0        ; 生产环境必须
opcache.revalidate_freq=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.enable_cli=0
; 小内存主机: 禁用 JIT 节省内存
opcache.jit_buffer_size=0
opcache.jit=disable
EOF

# PHP 基础安全配置
RUN cat > /usr/local/etc/php/conf.d/99-prod.ini <<'EOF'
date.timezone = Asia/Shanghai
display_errors = Off
log_errors = On
error_reporting = E_ALL & ~E_DEPRECATED
memory_limit = 128M          ; 严格限制
expose_php = Off
session.cookie_httponly = 1
session.cookie_secure = 1
allow_url_fopen = Off
EOF

# 创建目录 (非root运行)
RUN mkdir -p /app && chown -R www-data:www-data /app
WORKDIR /app

# PHP-FPM 进程优化 (小内存关键!)
RUN sed -i "s/pm.max_children = 5/pm.max_children = 8/g" /usr/local/etc/php-fpm.d/www.conf && \
    sed -i "s/pm.start_servers = 2/pm.start_servers = 2/g" /usr/local/etc/php-fpm.d/www.conf && \
    sed -i "s/pm.min_spare_servers = 1/pm.min_spare_servers = 1/g" /usr/local/etc/php-fpm.d/www.conf && \
    sed -i "s/pm.max_spare_servers = 3/pm.max_spare_servers = 3/g" /usr/local/etc/php-fpm.d/www.conf && \
    sed -i "s/;pm.max_requests = 500/pm.max_requests = 200/g" /usr/local/etc/php-fpm.d/www.conf

# 安全: 非 root 运行
USER www-data
EXPOSE 9000
CMD ["php-fpm"]
