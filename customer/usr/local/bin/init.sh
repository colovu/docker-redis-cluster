#!/bin/bash
# Ver: 1.2 by Endial Fang (endial@126.com)
# 
# 应用初始化脚本

# 设置 shell 执行参数，可使用'-'(打开）'+'（关闭）控制。常用：
# 	-e: 命令执行错误则报错; -u: 变量未定义则报错; -x: 打印实际待执行的命令行; -o pipefail: 设置管道中命令遇到失败则报错
set -eu
set -o pipefail

. /usr/local/bin/common-cluster.sh			# 应用专用函数库
. /usr/local/bin/environment.sh 			# 设置环境变量

LOG_I "** Processing init.sh **"

trap "${APP_NAME}_stop_server" EXIT

redis_cluster_verify_minimum_env

# 执行应用初始化操作
redis_cluster_default_init

if ! is_boolean_yes "$REDIS_CLUSTER_CREATOR" && is_boolean_yes "$REDIS_CLUSTER_DYNAMIC_IPS"; then
    redis_cluster_update_ips
fi
