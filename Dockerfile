# ==========================
# 生产环境及构建环境合一：使用推荐的 install-php-extensions 脚本 
# 自带依赖管理和构建后自动清理功能，极大减少了由于环境差异、配置文件路径不一致导致的问题
# ==========================
FROM php:8.2-fpm-alpine

# 2. 一键式无痕安装必需扩展
# 下载安装脚本 -> 赋予执行权限 -> 安装扩展 -> 安装完毕后彻底删除脚本（极限省空间）
RUN apk add --no-cache tzdata && \
    curl -sSLf \
        -o /usr/local/bin/install-php-extensions \
        https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions && \
    chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions redis mysqli pdo_mysql opcache gd exif imagick zip intl && \
    rm -f /usr/local/bin/install-php-extensions

# 4. 验证扩展是否成功加载并输出日志，避免构建出异常镜像
RUN php -m | grep -qi redis || (echo "ERROR: Redis not loaded" && exit 1) && \
    php -m | grep -qi mysqli || (echo "ERROR: MySQLi not loaded" && exit 1) && \
    php -m | grep -qi pdo_mysql || (echo "ERROR: PDO_MySQL not loaded" && exit 1) && \
    php -m | grep -qi opcache || (echo "ERROR: OPcache not loaded" && exit 1)

# 5. 针对低配机器（例如 ARM 2核2G）进行极致的 PHP 和 FPM 内存优化
# 目标：将内存占用控制在几十MB以内，同时保证 WordPress 良好运行
RUN set -ex; \
    # 基础配置：深度调优，确保大数据分析不超时并减少磁盘IO
    echo "memory_limit = 256M" > /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    echo "upload_max_filesize = 64M" >> /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    echo "post_max_size = 64M" >> /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    echo "max_execution_time = 300" >> /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    echo "realpath_cache_size = 4096k" >> /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    echo "realpath_cache_ttl = 600" >> /usr/local/etc/php/conf.d/zz-optimizations.ini; \
    # OPcache 优化：限制缓存大小，避免占用过多内存 (32MB 分配给 OPcache)
    # OPcache 优化：调大缓存，减少硬盘读取延迟
    echo "opcache.enable=1" > /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.memory_consumption=128" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.interned_strings_buffer=16" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.max_accelerated_files=10000" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.revalidate_freq=60" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.enable_cli=0" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    # 彻底禁用 JIT (Just-In-Time) 编译，因为它会额外消耗大量内存，这对低配机器非常致命
    echo "opcache.jit=disable" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    echo "opcache.jit_buffer_size=0" >> /usr/local/etc/php/conf.d/zz-opcache.ini; \
    # FPM 进程池优化：这是省内存的核心
    # 采用 ondemand 模式，没请求就休眠，max_children = 15 保证 Simply Static 抓取时不假死
    # FPM 进程池优化：从 ondemand 改为 dynamic，保持 PHP 进程常驻，杜绝启动卡顿
    echo "[www]" > /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm = dynamic" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.max_children = 10" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.start_servers = 2" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.min_spare_servers = 1" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.max_spare_servers = 3" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf; \
    echo "pm.max_requests = 500" >> /usr/local/etc/php-fpm.d/zz-low-memory.conf

# 设置工作目录
WORKDIR /app

# 启动 php-fpm
CMD ["php-fpm"]
