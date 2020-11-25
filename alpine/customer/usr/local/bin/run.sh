#!/bin/bash
# Ver: 1.1 by Endial Fang (endial@126.com)
# 
# 应用启动脚本

# 设置 shell 执行参数，可使用'-'(打开）'+'（关闭）控制。常用：
# 	-e: 命令执行错误则报错; -u: 变量未定义则报错; -x: 打印实际待执行的命令行; -o pipefail: 设置管道中命令遇到失败则报错
set -eu
set -o pipefail

. /usr/local/bin/comm-redis-cluster.sh			# 应用专用函数库

. /usr/local/bin/comm-env.sh 			# 设置环境变量

LOG_I "** Processing run.sh **"

IFS=' ' read -ra nodes <<< "$REDIS_CLUSTER_NODES"

if ! is_boolean_yes "$REDIS_CLUSTER_CREATOR"; then
	# 配置默认启动参数（应用配置文件、前台方式启动）
	flags=("${REDIS_CONF_FILE:-}" "--daemonize" "no")
	# 将启动时使用 REDIS_EXTRA_FLAGS 指定的参数附加在启动参数中
	[[ -z "${REDIS_EXTRA_FLAGS:-}" ]] || flags+=("${REDIS_EXTRA_FLAGS[@]}")
	# 将启动时的传入参数附加在参数中
	flags+=("$@")

	# 设置启动命令
	START_COMMAND=("redis-server")

	LOG_I "** Starting ${APP_NAME} **"
	if is_root; then
	    exec gosu "${APP_USER}" "${START_COMMAND[@]}" "${flags[@]}"
	else
	    exec "${START_COMMAND[@]}" "${flags[@]}"
	fi
else
    redis_cluster_create "${nodes[@]}"
fi
