FROM php:8.2-fpm-alpine AS builder

# 安装编译依赖
# 注意：这里只有软件包名称，绝对没有目录路径！
RUN apk add --no-cache \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    make \
    g++ \
    linux-headers \
    hiredis-dev \
    && pecl install redis \
    && docker-php-ext-enable redis

FROM php:8.2-fpm-alpine

# 复制编译好的扩展文件
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-*/redis.so /usr/local/lib/php/extensions/no-debug-non-zts-*/redis.so
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/docker-php-ext-redis.ini

# 验证
RUN php -m | grep -q redis || (echo "Redis extension load failed" && exit 1)

WORKDIR /app
CMD ["php-fpm"]
