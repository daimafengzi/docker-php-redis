# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 安装运行时依赖
RUN apk add --no-cache mariadb-connector-c

# 定义扩展目录
ENV PHP_EXT_DIR=/usr/local/lib/php/extensions/no-debug-non-zts-20220829

# 创建目录
RUN mkdir -p ${PHP_EXT_DIR}

# 复制 .so 文件
COPY --from=builder ${PHP_EXT_DIR}/redis.so ${PHP_EXT_DIR}/redis.so
COPY --from=builder ${PHP_EXT_DIR}/pdo_mysql.so ${PHP_EXT_DIR}/pdo_mysql.so
COPY --from=builder ${PHP_EXT_DIR}/mysqli.so ${PHP_EXT_DIR}/mysqli.so

# 👇👇👇 关键修复：显式创建 .ini 文件（不依赖 builder）👇👇👇
RUN echo "extension=redis.so" > /usr/local/etc/php/conf.d/99-redis.ini && \
    echo "extension=pdo_mysql.so" > /usr/local/etc/php/conf.d/99-pdo_mysql.ini && \
    echo "extension=mysqli.so" > /usr/local/etc/php/conf.d/99-mysqli.ini

# 验证 FPM 能加载 mysqli（这步会失败如果没修好）
RUN php-fpm -m | grep -q mysqli || (echo "FATAL: mysqli not loaded in FPM!" && exit 1)

WORKDIR /app
CMD ["php-fpm"]
