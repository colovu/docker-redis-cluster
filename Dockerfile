# Ver: 1.8 by Endial Fang (endial@126.com)
#

# 可变参数 ========================================================================

# 设置当前应用名称及版本
ARG app_name=redis
ARG app_version=6.0.9

# 设置默认仓库地址，默认为 阿里云 仓库
ARG registry_url="registry.cn-shenzhen.aliyuncs.com"

# 设置 apt-get 源：default / tencent / ustc / aliyun / huawei
ARG apt_source=aliyun

# 编译镜像时指定用于加速的本地服务器地址
ARG local_url=""


# 0. 预处理 ======================================================================
FROM ${registry_url}/colovu/dbuilder as builder

# 声明需要使用的全局可变参数
ARG app_name
ARG app_version
ARG registry_url
ARG apt_source
ARG local_url


ENV APP_NAME=${app_name} \
	APP_VERSION=${app_version}

# 选择软件包源(Optional)，以加速后续软件包安装
RUN select_source ${apt_source};

# 安装依赖的软件包及库(Optional)
#RUN install_pkg xz-utils

# 设置工作目录
WORKDIR /tmp

# 下载并解压软件包
RUN set -eux; \
	appName="${APP_NAME}-${APP_VERSION}.tar.gz"; \
	sha256="dc2bdcf81c620e9f09cfd12e85d3bc631c897b2db7a55218fd8a65eaa37f86dd"; \
	[ ! -z ${local_url} ] && localURL=${local_url}/${APP_NAME}; \
	appUrls="${localURL:-} \
		http://download.redis.io/releases \
		"; \
	download_pkg unpack ${appName} "${appUrls}" -s "${sha256}";

# 源码编译: 编译后将配置文件模板拷贝至 /usr/local/${APP_NAME}/share/${APP_NAME} 中
RUN set -eux; \
	APP_SRC="/tmp/${APP_NAME}-${APP_VERSION}"; \
	cd ${APP_SRC}; \
# 禁用安全保护模式，在 Docker 中运行时不需要
	grep -E '^ *createBoolConfig[(]"protected-mode",.*, *1 *,.*[)],$' ./src/config.c; \
	sed -ri 's!^( *createBoolConfig[(]"protected-mode",.*, *)1( *,.*[)],)$!\10\2!' ./src/config.c; \
	grep -E '^ *createBoolConfig[(]"protected-mode",.*, *0 *,.*[)],$' ./src/config.c; \
	make MALLOC=libc BUILD_TLS=yes \
		-j "$(nproc)" all; \
	make PREFIX=/usr/local/${APP_NAME} install;  \
# 将配置文件模板拷贝至应用安装目录的 etc/${APP_NAME} 目录下
	mkdir -p /usr/local/${APP_NAME}/etc/${APP_NAME}; \
	cp /tmp/${APP_NAME}-${APP_VERSION}/*.conf /usr/local/${APP_NAME}/etc/${APP_NAME}/; \
# 删除重复的应用程序，并生成对应的连接
	serverMd5="$(md5sum /usr/local/redis/bin/redis-server | cut -d' ' -f1)"; export serverMd5; \
	find /usr/local/redis/bin/redis* -maxdepth 0 \
		-type f -not -name redis-server \
		-exec sh -eux -c ' \
			md5="$(md5sum "$1" | cut -d" " -f1)"; \
			test "$md5" = "$serverMd5"; \
		' -- '{}' ';' \
		-exec ln -svfT 'redis-server' '{}' ';' ; 

# 删除编译生成的多余文件
RUN set -eux; \
	find /usr/local -name '*.a' -delete; \
	rm -rf /usr/local/${APP_NAME}/include;

# 检测并生成依赖文件记录
RUN set -eux; \
	find /usr/local/${APP_NAME} -type f -executable -exec ldd '{}' ';' | \
		awk '/=>/ { print $(NF-1) }' | \
		sort -u | \
		xargs -r dpkg-query --search 2>/dev/null | \
		cut -d: -f1 | \
		sort -u >/usr/local/${APP_NAME}/runDeps;


# 1. 生成镜像 =====================================================================
FROM ${registry_url}/colovu/debian:buster

# 声明需要使用的全局可变参数
ARG app_name
ARG app_version
ARG registry_url
ARG apt_source
ARG local_url

# 镜像所包含应用的基础信息，定义环境变量，供后续脚本使用
ENV APP_NAME=${app_name} \
	APP_USER=${app_name} \
	APP_EXEC=redis-server \
	APP_VERSION=${app_version}

ENV	APP_HOME_DIR=/usr/local/${APP_NAME} \
	APP_DEF_DIR=/etc/${APP_NAME}

ENV PATH="${APP_HOME_DIR}/sbin:${APP_HOME_DIR}/bin:${PATH}" \
	LD_LIBRARY_PATH="${APP_HOME_DIR}/lib"

LABEL \
	"Version"="v${APP_VERSION}" \
	"Description"="Docker image for ${APP_NAME}(v${APP_VERSION})." \
	"Dockerfile"="https://github.com/colovu/docker-${APP_NAME}" \
	"Vendor"="Endial Fang (endial@126.com)"

# 从预处理过程中拷贝软件包(Optional)，可以使用阶段编号或阶段命名定义来源
COPY --from=0 /usr/local/${APP_NAME} /usr/local/${APP_NAME}

# 拷贝应用使用的客制化脚本，并创建对应的用户及数据存储目录
COPY customer /
RUN set -eux; \
	prepare_env; \
	/bin/bash -c "ln -sf /usr/local/${APP_NAME}/etc/${APP_NAME} /etc/";

# 选择软件包源(Optional)，以加速后续软件包安装
RUN select_source ${apt_source}

# 安装依赖的软件包及库(Optional)
RUN install_pkg `cat /usr/local/${APP_NAME}/runDeps`; 
RUN install_pkg netcat;

# 执行预处理脚本，并验证安装的软件包
RUN set -eux; \
	override_file="/usr/local/overrides/overrides-${APP_VERSION}.sh"; \
	[ -e "${override_file}" ] && /bin/bash "${override_file}"; \
	redis-cli --version; \
	${APP_EXEC} --version;

# 默认提供的数据卷
VOLUME ["/srv/conf", "/srv/data", "/srv/datalog", "/srv/cert", "/var/log"]

# 默认non-root用户启动，必须保证端口在1024之上
EXPOSE 6379

# 关闭基础镜像的健康检查
#HEALTHCHECK NONE

# 应用健康状态检查
#HEALTHCHECK --interval=30s --timeout=30s --retries=3 \
#	CMD curl -fs http://localhost:8080/ || exit 1
HEALTHCHECK --interval=10s --timeout=10s --retries=3 \
	CMD netstat -ltun | grep 6379

# 使用 non-root 用户运行后续的命令
USER 1001

# 设置工作目录
WORKDIR /srv/data

# 容器初始化命令
ENTRYPOINT ["/usr/local/bin/entry.sh"]

# 应用程序的启动命令，必须使用非守护进程方式运行
CMD ["/usr/local/bin/run.sh"]

