FROM php:8.2-fpm-alpine AS builder

# 安装编译依赖
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

# 【优化点】
# 1. 先找出 builder 中 redis.so 的确切路径
# 2. 确保目标目录存在 (PHP 8.2 通常是 no-debug-non-zts-20220829)
# 3. 进行复制

# 获取 PHP 扩展目录的版本号后缀 (例如 20220829)
# 这样写比硬编码或通配符更安全，能适应 PHP 小版本升级
RUN PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');") && \
    EXT_VERSION=$(basename $PHP_EXT_DIR) && \
    mkdir -p /usr/local/lib/php/extensions/$EXT_VERSION && \
    # 从 builder 复制 .so 文件
    # 注意：这里依然可以使用通配符，因为源路径是确定的，但为了保险，我们分两步走
    echo "Target extension dir: $EXT_VERSION"

# 复制 .so 文件 (使用通配符匹配源，指定具体版本目标)
# 如果通配符在 COPY 中失效，这是最可能的原因。
# 更稳妥的方式是利用 shell 在 RUN 中复制，或者确认通配符有效。
# 实际上，Docker COPY 支持通配符，但为了绝对清晰，我们可以这样写：
COPY --from=builder /usr/local/lib/php/extensions/*/redis.so /tmp/redis.so

# 动态获取目标目录并移动文件
RUN PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');") && \
    cp /tmp/redis.so $PHP_EXT_DIR/redis.so && \
    rm /tmp/redis.so

# 复制 ini 配置文件
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/

# 验证 (如果失败，构建直接停止，不会推送坏镜像)
RUN php -m | grep -q redis || (echo "❌ Redis extension load failed" && exit 1)

WORKDIR /app
CMD ["php-fpm"]
