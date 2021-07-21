#!/bin/bash
# Ver: 1.0 by Endial Fang (endial@126.com)
# 
# 应用环境变量定义及初始化

# 通用设置
export ENV_DEBUG=${ENV_DEBUG:-false}
export ALLOW_ANONYMOUS_LOGIN="${ALLOW_ANONYMOUS_LOGIN:-no}"

# 通过读取变量名对应的 *_FILE 文件，获取变量值；如果对应文件存在，则通过传入参数设置的变量值会被文件中对应的值覆盖
# 变量优先级： *_FILE > 传入变量 > 默认值
app_env_file_lists=(
	REDIS_PASSWORD
	REDIS_MASTER_PASSWORD
)
for env_var in "${app_env_file_lists[@]}"; do
    file_env_var="${env_var}_FILE"
    if [[ -n "${!file_env_var:-}" ]]; then
        export "${env_var}=$(< "${!file_env_var}")"
        unset "${file_env_var}"
    fi
done
unset app_env_file_lists

# 应用路径参数
export APP_HOME_DIR="/usr/local/${APP_NAME}"
export APP_DEF_DIR="/etc/${APP_NAME}"
export APP_CONF_DIR="/srv/conf/${APP_NAME}"
export APP_DATA_DIR="/srv/data/${APP_NAME}"
export APP_DATA_LOG_DIR="/srv/datalog/${APP_NAME}"
export APP_CACHE_DIR="/var/cache/${APP_NAME}"
export APP_RUN_DIR="/var/run/${APP_NAME}"
export APP_LOG_DIR="/var/log/${APP_NAME}"
export APP_CERT_DIR="/srv/cert/${APP_NAME}"

# Paths
export REDIS_CONF_FILE="${APP_CONF_DIR}/redis.conf"
export REDIS_SENTINEL_FILE="${APP_CONF_DIR}/sentinel.conf"
export REDIS_PID_FILE="${APP_RUN_DIR}/redis.pid"

# Redis settings
export REDIS_PORT="${REDIS_PORT:-6379}"
export REDIS_DISABLE_COMMANDS="${REDIS_DISABLE_COMMANDS:-}"
export REDIS_AOF_ENABLED="${REDIS_AOF_ENABLED:-yes}"

# Cluster configuration
export REDIS_SENTINEL_HOST="${REDIS_SENTINEL_HOST:-}"
export REDIS_SENTINEL_MASTER_NAME="${REDIS_SENTINEL_MASTER_NAME:-}"
export REDIS_SENTINEL_PORT_NUMBER="${REDIS_SENTINEL_PORT_NUMBER:-26379}"

export REDIS_MASTER_HOST="${REDIS_MASTER_HOST:-}"
export REDIS_MASTER_PORT_NUMBER="${REDIS_MASTER_PORT_NUMBER:-6379}"
export REDIS_MASTER_PASSWORD="${REDIS_MASTER_PASSWORD:-}"
export REDIS_REPLICATION_MODE="${REDIS_REPLICATION_MODE:-}"

# Redis TLS Settings
export REDIS_TLS_ENABLED="${REDIS_TLS_ENABLED:-no}"
export REDIS_TLS_PORT="${REDIS_TLS_PORT:-6379}"
export REDIS_TLS_CERT_FILE="${REDIS_TLS_CERT_FILE:-}"
export REDIS_TLS_KEY_FILE="${REDIS_TLS_KEY_FILE:-}"
export REDIS_TLS_CA_FILE="${REDIS_TLS_CA_FILE:-}"
export REDIS_TLS_DH_PARAMS_FILE="${REDIS_TLS_DH_PARAMS_FILE:-}"
export REDIS_TLS_AUTH_CLIENTS="${REDIS_TLS_AUTH_CLIENTS:-yes}"

# Authentication
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# 应用配置参数

# Redis Cluster settings
export REDIS_CLUSTER_CREATOR="${REDIS_CLUSTER_CREATOR:-no}"
export REDIS_CLUSTER_REPLICAS="${REDIS_CLUSTER_REPLICAS:-1}"
export REDIS_CLUSTER_NODES="${REDIS_CLUSTER_NODES:-}"
export REDIS_CLUSTER_DYNAMIC_IPS="${REDIS_CLUSTER_DYNAMIC_IPS:-yes}"
export REDIS_CLUSTER_ANNOUNCE_IP="${REDIS_CLUSTER_ANNOUNCE_IP:-}"
export REDIS_DNS_RETRIES="${REDIS_DNS_RETRIES:-120}"

# 内部变量
export APP_PID_FILE="${REDIS_PID_FILE:-${APP_RUN_DIR}/${APP_NAME}.pid}"

export APP_DAEMON_USER="${APP_NAME}"
export APP_DAEMON_GROUP="${APP_NAME}"

# 个性化变量
# 如果设置了用户密码，设置环境变量 REDISCLI_AUTH，用于 `redis-cli` 登录时使用；不显示输入，保证安全
if [[ -n "${REDIS_PASSWORD}" ]]; then
	export REDISCLI_AUTH="${REDIS_PASSWORD:-}"
fi
