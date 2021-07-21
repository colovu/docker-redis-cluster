#!/bin/bash
# Ver: 1.3 by Endial Fang (endial@126.com)
# 
# 应用启动脚本

# 设置 shell 执行参数，可使用'-'(打开）'+'（关闭）控制。常用：
# 	-e: 命令执行错误则报错(errexit); -u: 变量未定义则报错(nounset); -x: 打印实际待执行的命令行; -o pipefail: 设置管道中命令遇到失败则报错
set -eu
set -o pipefail

. /usr/local/bin/common-cluster.sh				# 应用专用函数库
. /usr/local/bin/environment.sh 				# 设置环境变量

LOG_I "** Processing run.sh **"

readonly START_COMMAND="$(command -v ${APP_EXEC})"

IFS=' ' read -ra nodes <<< "$REDIS_CLUSTER_NODES"

if ! is_boolean_yes "$REDIS_CLUSTER_CREATOR"; then
	# 配置默认启动参数（应用配置文件、前台方式启动）
	flags=("${REDIS_CONF_FILE:-}" "--daemonize" "no")
	# 将启动时使用 REDIS_EXTRA_FLAGS 指定的参数附加在启动参数中
	[[ -z "${REDIS_EXTRA_FLAGS:-}" ]] || flags+=("${REDIS_EXTRA_FLAGS[@]}")
	# 增加 "@" 以使用用户在命令行添加的扩展标识
	flags+=("$@")

	LOG_I "** Starting ${APP_NAME} **"
	#is_root && flags=("-u" "$APP_DAEMON_USER" "${flags[@]}")
	
	LOG_I "Command: ${START_COMMAND[@]} ${flags[@]}"
	exec "${START_COMMAND[@]}" "${flags[@]}"
else
    redis_cluster_create "${nodes[@]}"
fi
