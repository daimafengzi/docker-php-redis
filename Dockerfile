# Dockerfile
FROM php:8.2-fpm-alpine AS builder

# 安装编译所需的临时依赖
RUN apk add --no-cache \
    hiredis-dev \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    make \
    g++ \
    linux-headers \
    $PHP_INI_DIR/conf.d \
    && pecl install redis \
    && docker-php-ext-enable redis

# 最终运行阶段：只复制编译好的扩展，丢弃庞大的编译工具
FROM php:8.2-fpm-alpine

# 从 builder 阶段复制编译好的 redis 扩展配置和.so文件
# 注意：pecl install 通常会在 conf.d 生成 ini 文件，并在 modules 生成 so 文件
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-*/redis.so /usr/local/lib/php/extensions/no-debug-non-zts-*/redis.so
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/docker-php-ext-redis.ini

# 验证扩展是否加载 (可选，构建时会运行)
RUN php -m | grep -q redis || (echo "Redis extension failed to load" && exit 1)

WORKDIR /app

CMD ["php-fpm"]
