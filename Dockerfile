# ==========================
# 阶段 1: Builder (编译环境)
# ==========================
FROM php:8.2-fpm-alpine AS builder

# 安装编译依赖
RUN apk add --no-cache \
    $PHPIZE_DEPS \
    linux-headers \
    hiredis-dev \
    mariadb-dev \
    autoconf \
    automake

# 1. 安装 Redis (PECL 方式)
RUN pecl install redis \
    && docker-php-ext-enable redis

# 2. 安装 PDO MySQL (官方脚本方式)
RUN docker-php-ext-install pdo_mysql

# ==========================
# 阶段 2: Production (生产环境)
# ==========================
FROM php:8.2-fpm-alpine

# 1. 安装运行时依赖 (必须，否则连不上库)
RUN apk add --no-cache mariadb-connector-c

# 2. 动态获取当前 PHP 的扩展目录路径 (最稳妥的做法)
# 这样即使 PHP 升级，路径也会自动适配
RUN set -ex; \
    PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');"); \
    mkdir -p "$PHP_EXT_DIR"; \
    echo "Extension dir detected: $PHP_EXT_DIR"

# 3. 【关键修复】从 Builder 复制扩展文件 (.so)
# 使用通配符 */ 来匹配具体的子目录，防止路径写死
COPY --from=builder /usr/local/lib/php/extensions/*/redis.so "$PHP_EXT_DIR/redis.so"
COPY --from=builder /usr/local/lib/php/extensions/*/pdo_mysql.so "$PHP_EXT_DIR/pdo_mysql.so"

# 4. 复制配置文件 (.ini)
# 虽然 docker-php-ext-enable 通常会自动处理，但显式复制更保险
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-redis.ini /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

# 5. 【终极验证】在镜像构建阶段就检查！
# 如果这一步失败，GitHub Actions 会变红，你根本不会去拉取坏镜像
RUN set -ex; \
    php -m | grep -q redis || (echo "❌ FATAL: Redis extension missing!" && exit 1); \
    php -m | grep -q pdo_mysql || (echo "❌ FATAL: PDO MySQL extension missing!" && exit 1); \
    php -r "if (!defined('PDO::MYSQL_ATTR_INIT_COMMAND')) { echo '❌ FATAL: Constant missing!'; exit(1); }"; \
    echo "✅ All checks passed. Image is safe to deploy."

WORKDIR /app

CMD ["php-fpm"]
