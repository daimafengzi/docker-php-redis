FROM php:8.2-fpm-alpine AS builder

# 只安装最核心的编译工具，去掉可能有问题的 hiredis-dev
RUN apk add --no-cache \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    make \
    g++ \
    linux-headers \
    && pecl install redis \
    && docker-php-ext-enable redis

FROM php:8.2-fpm-alpine

COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-*/redis.so /usr/local/lib/php/extensions/no-debug-non-zts-*/redis.so
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/docker-php-ext-redis.ini

RUN php -m | grep -q redis || (echo "Redis extension load failed" && exit 1)

WORKDIR /app
CMD ["php-fpm"]
