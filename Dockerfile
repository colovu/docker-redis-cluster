# Ver: 1.3 by Endial Fang (endial@126.com)
#

# 预处理 =========================================================================
FROM colovu/dbuilder as builder

# sources.list 可使用版本：default / tencent / ustc / aliyun / huawei
ARG apt_source=default

# 编译镜像时指定用于加速的本地服务器地址
ARG local_url=""

ENV APP_NAME=redis \
	APP_VERSION=5.0.9

RUN select_source ${apt_source};
#RUN install_pkg xz-utils

# 下载并解压软件包
RUN set -eux; \
	appName="${APP_NAME}-${APP_VERSION}.tar.gz"; \
	sha256="53d0ae164cd33536c3d4b720ae9a128ea6166ebf04ff1add3b85f1242090cb85"; \
	[ ! -z ${local_url} ] && localURL=${local_url}/${APP_NAME}; \
	appUrls="${localURL:-} \
		http://download.redis.io/releases \
		"; \
	download_pkg unpack ${appName} "${appUrls}" -s "${sha256}";

# 源码编译: 编译后将配置文件模板拷贝至 /usr/local/${APP_NAME}/share/${APP_NAME} 中
RUN set -eux; \
	APP_SRC="/usr/local/${APP_NAME}-${APP_VERSION}"; \
	cd ${APP_SRC}; \
# 禁用安全保护模式，在 Docker 中运行时不需要
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' ./src/server.h; \
	sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' ./src/server.h; \
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' ./src/server.h; \
	make MALLOC=libc BUILD_TLS=yes \
		-j "$(nproc)" all; \
	make PREFIX=/usr/local/${APP_NAME} install;  \
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
		xargs -r dpkg-query --search | \
		cut -d: -f1 | \
		sort -u >/usr/local/${APP_NAME}/runDeps;

# 镜像生成 ========================================================================
FROM colovu/debian:10

ARG apt_source=default
ARG local_url=""

ENV APP_NAME=redis \
	APP_USER=redis \
	APP_EXEC=run.sh \
	APP_VERSION=5.0.9

ENV	APP_HOME_DIR=/usr/local/${APP_NAME} \
	APP_DEF_DIR=/etc/${APP_NAME}

ENV PATH="${APP_HOME_DIR}/bin:${PATH}" \
	LD_LIBRARY_PATH="${APP_HOME_DIR}/lib"

LABEL \
	"Version"="v${APP_VERSION}" \
	"Description"="Docker image for ${APP_NAME}(v${APP_VERSION})." \
	"Dockerfile"="https://github.com/colovu/docker-${APP_NAME}" \
	"Vendor"="Endial Fang (endial@126.com)"

# 选择软件包源
RUN select_source ${apt_source}

COPY customer /
RUN create_user && prepare_env

# 从预处理过程中拷贝软件包(Optional)
COPY --from=builder /usr/local/${APP_NAME}/ /usr/local/${APP_NAME}
COPY --from=builder /usr/local/${APP_NAME}-${APP_VERSION}/*.conf /etc/${APP_NAME}/

# 安装依赖的软件包及库(Optional)
RUN install_pkg `cat /usr/local/${APP_NAME}/runDeps`; 
RUN install_pkg netcat;

# 执行预处理脚本，并验证安装的软件包
RUN set -eux; \
	override_file="/usr/local/overrides/overrides-${APP_VERSION}.sh"; \
	[ -e "${override_file}" ] && /bin/bash "${override_file}"; \
	gosu ${APP_USER} redis-cli --version; \
	gosu ${APP_USER} redis-server --version; \
	gosu --version;

# 默认提供的数据卷
VOLUME ["/srv/conf", "/srv/data", "/srv/datalog", "/srv/cert", "/var/log"]

# 默认使用gosu切换为新建用户启动，必须保证端口在1024之上
EXPOSE 6379

# 容器初始化命令，默认存放在：/usr/local/bin/entry.sh
ENTRYPOINT ["entry.sh"]

# 应用程序的服务命令，必须使用非守护进程方式运行。如果使用变量，则该变量必须在运行环境中存在（ENV可以获取）
CMD ["${APP_EXEC}"]

