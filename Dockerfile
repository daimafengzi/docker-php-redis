# ==========================
# 生产环境及构建环境合一：使用推荐的 install-php-extensions 脚本
# 自带依赖管理和构建后自动清理功能，极大减少了由于环境差异、配置文件路径不一致导致的问题
# ==========================
FROM php:8.2-fpm-alpine

# 1. 安装基础工具库
RUN apk add --no-cache tzdata

# 2. 安装官方推荐的便捷扩展安装脚本（稳定、自动处理依赖并清理源文件）
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# 3. 安装 WordPress 必需的数据库扩展(mysqli)及 Redis、OPcache 扩展
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions redis mysqli opcache

# 4. 验证扩展是否成功加载并输出日志，避免构建出异常镜像
RUN php -m | grep -qi redis || (echo "ERROR: Redis not loaded" && exit 1) && \
    php -m | grep -qi mysqli || (echo "ERROR: MySQLi not loaded" && exit 1) && \
    php -m | grep -qi opcache || (echo "ERROR: OPcache not loaded" && exit 1)

# 5. 针对低配机器（例如 ARM 2核2G）进行极致的 PHP 和 FPM 内存优化
# 目标：将内存占用控制在几十MB以内，同时保证 WordPress 良好运行
RUN set -ex; \
    # 基础配置：限制最大内存
    echo "memory_limit = 128M" > /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    echo "upload_max_filesize = 32M" >> /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    echo "post_max_size = 32M" >> /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    # OPcache 优化：限制缓存大小，避免占用过多内存 (32MB 分配给 OPcache)
    echo "opcache.enable=1" > /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.memory_consumption=32" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.interned_strings_buffer=8" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.max_accelerated_files=5000" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.revalidate_freq=60" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.enable_cli=0" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    # 彻底禁用 JIT (Just-In-Time) 编译，因为它会额外消耗大量内存，这对低配机器非常致命
    echo "opcache.jit=disable" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.jit_buffer_size=0" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    # FPM 进程池优化：这是省内存的核心
    # 采用 ondemand 模式，没请求就休眠，max_children = 4 保证极端请求下不崩
    echo "[www]" > /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm = ondemand" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.max_children = 4" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.process_idle_timeout = 10s" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.max_requests = 500" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf

# 设置工作目录
WORKDIR /app

# 启动 php-fpm
CMD ["php-fpm"]
