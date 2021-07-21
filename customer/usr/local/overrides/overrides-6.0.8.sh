#!/bin/bash -e
# Ver: 1.0 by Endial Fang (endial@126.com)
#
# 在安装完应用后，使用该脚本修改默认配置文件中部分配置项; 如果相应的配置项已经定义为容器环境变量，则不需要在这里修改

# 定义要修改的文件
CONF_FILE="${APP_DEF_DIR}/redis.conf"
echo "Process overrides for: ${CONF_FILE}"
# 修改默认配置信息
sed -i -E 's/^#?pidfile .*/pidfile \/var\/run\/redis\/redis.pid/g' "${CONF_FILE}"
sed -i -E 's/^#?logfile .*/logfile \"\/var\/log\/redis\/redis.log\"/g' "${CONF_FILE}"

SENTINEL_FILE="${APP_DEF_DIR}/sentinel.conf"
echo "Process overrides for: ${SENTINEL_FILE}"
# 修改 Sentinel 默认配置信息
sed -i -E 's/^#?pidfile .*/pidfile \/var\/run\/redis\/redis-sentinel.pid/g' "${SENTINEL_FILE}"
sed -i -E 's/^#?logfile .*/logfile \"\/var\/log\/redis\/redis-sentinel.log\"/g' "${SENTINEL_FILE}"
