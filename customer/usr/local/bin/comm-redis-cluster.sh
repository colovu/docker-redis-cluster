#!/bin/bash
# Ver: 1.0 by Endial Fang (endial@126.com)
# 
# 集群应用通用业务处理函数

# 加载依赖脚本
. /usr/local/scripts/libcommon.sh       # 通用函数库

. /usr/local/scripts/libfile.sh
. /usr/local/scripts/libfs.sh
. /usr/local/scripts/libos.sh
. /usr/local/scripts/libnet.sh
. /usr/local/scripts/libservice.sh
. /usr/local/scripts/libvalidations.sh

. /usr/local/bin/comm-redis.sh

# 函数库

# 检测用户参数信息是否满足条件; 针对部分权限过于开放情况，打印提示信息
redis_cluster_verify_minimum_env() {
    LOG_D "Validating settings in REDIS_* env vars.."
    local error_code=0

    # Auxiliary functions
    print_validation_error() {
        LOG_E "$1"
        error_code=1
    }

    empty_password_enabled_warn() {
        LOG_W "You set the environment variable ALLOW_ANONYMOUS_LOGIN=${ALLOW_ANONYMOUS_LOGIN}. For safety reasons, do not use this flag in a production environment."
    }
    empty_password_error() {
        print_validation_error "The $1 environment variable is empty or not set. Set the environment variable ALLOW_ANONYMOUS_LOGIN=yes to allow the container to be started with blank passwords. This is recommended only for development."
    }

    if is_boolean_yes "$ALLOW_ANONYMOUS_LOGIN"; then
        empty_password_enabled_warn
    else
        if ! is_boolean_yes "$REDIS_CLUSTER_CREATOR"; then
            [[ -z "$REDIS_PASSWORD" ]] && empty_password_error REDIS_PASSWORD
        fi
    fi

    if ! is_boolean_yes "$REDIS_CLUSTER_DYNAMIC_IPS"; then
        if ! is_boolean_yes "$REDIS_CLUSTER_CREATOR"; then
            [[ -z "$REDIS_CLUSTER_ANNOUNCE_IP" ]] && print_validation_error "To provide external access you need to provide the REDIS_CLUSTER_ANNOUNCE_IP env var"
        fi
    fi

    [[ -z "$REDIS_CLUSTER_NODES" ]] && print_validation_error "REDIS_CLUSTER_NODES is required"

    if [[ -z "$REDIS_PORT" ]]; then
        print_validation_error "REDIS_PORT cannot be empty"
    fi

    if is_boolean_yes "$REDIS_CLUSTER_CREATOR"; then
        [[ -z "$REDIS_CLUSTER_REPLICAS" ]] && print_validation_error "To create the cluster you need to provide the number of replicas"
    fi

    [[ "$error_code" -eq 0 ]] || exit "$error_code"
}

# 更新默认配置文件中配置项
redis_cluster_override_conf() {
    if ! (is_boolean_yes "$REDIS_CLUSTER_DYNAMIC_IPS" || is_boolean_yes "$REDIS_CLUSTER_CREATOR"); then
        redis_conf_set cluster-announce-ip "$REDIS_CLUSTER_ANNOUNCE_IP"
    fi
    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        redis_conf_set tls-cluster yes
        redis_conf_set tls-replication yes
    fi

    redis_conf_set cluster-enabled yes
    redis_conf_set cluster-config-file "${APP_DATA_DIR}/nodes.conf"
}

# 初始化 Redis 配置文件
redis_cluster_default_init() {
    # 执行应用预初始化操作
    redis_custom_preinit

    # 执行应用初始化操作
    redis_default_init

    # 执行用户自定义初始化脚本
    redis_custom_init

    redis_cluster_override_conf
}

# 创建 Redis 集群
# 参数:
#   - $@ 主机名数组
redis_cluster_create() {
  local nodes=("$@")
  local ips=()
  local wait_command
  local create_command

  for node in "${nodes[@]}"; do
      if is_boolean_yes "$REDIS_TLS_ENABLED"; then
          wait_command="redis-cli -h ${node} -p ${REDIS_TLS_PORT} --tls --cert ${REDIS_TLS_CERT_FILE} --key ${REDIS_TLS_KEY_FILE} --cacert ${REDIS_TLS_CA_FILE} ping"
      else
          wait_command="redis-cli -h ${node} -p ${REDIS_PORT} ping"
      fi
      while [[ $($wait_command) != 'PONG' ]]; do
          LOG_D "Node $node not ready, waiting for all the nodes to be ready..."
          sleep 1
      done
      ips+=($(dns_lookup "$node"))
  done

  if is_boolean_yes "$REDIS_TLS_ENABLED"; then
      create_command="redis-cli --cluster create ${ips[*]/%/:${REDIS_TLS_PORT}} --cluster-replicas ${REDIS_CLUSTER_REPLICAS} --cluster-yes --tls --cert ${REDIS_TLS_CERT_FILE} --key ${REDIS_TLS_KEY_FILE} --cacert ${REDIS_TLS_CA_FILE}"
  else
      create_command="redis-cli --cluster create ${ips[*]/%/:${REDIS_PORT}} --cluster-replicas ${REDIS_CLUSTER_REPLICAS} --cluster-yes"
  fi
  yes yes | $create_command || true
  if redis_cluster_check "${ips[0]}"; then
      LOG_I "Cluster correctly created"
  else
      LOG_I "The cluster was already created, the nodes should have recovered it"
  fi
}

# 检查集群状态是否正常
# 参数:
#  - $1: 集群中任一主机名
redis_cluster_check() {
    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        local -r check=$(redis-cli --tls --cert "${REDIS_TLS_CERT_FILE}" --key "${REDIS_TLS_KEY_FILE}" --cacert "${REDIS_TLS_CA_FILE}" --cluster check "$1":"$REDIS_TLS_PORT")
    else
        local -r check=$(redis-cli --cluster check "$1":"$REDIS_PORT")
    fi
    if [[ $check =~ "All 16384 slots covered" ]]; then
        true
    else
        false
    fi
}

# 当使用动态 IP 时，使用实际 IP 地址更新节点配置文件 node.conf
redis_cluster_update_ips() {
    IFS=' ' read -ra nodes <<< "$REDIS_CLUSTER_NODES"

    # 定义 主机：IP 对应数组
    declare -A host_2_ip_array

    if [[ ! -f  "${APP_DATA_DIR}/nodes.sh" ]]; then
        # 新初始化的集群
        for node in "${nodes[@]}"; do
            ip=$(wait_for_dns_lookup "$node" "$REDIS_DNS_RETRIES" 5)
            host_2_ip_array["$node"]="$ip"
        done
        LOG_I "Storing map with hostnames and IPs"
        declare -p host_2_ip_array > "${APP_DATA_DIR}/nodes.sh"
    else
        # 已启动的集群
        . "${APP_DATA_DIR}/nodes.sh"
        # 更新配置文件 nodes.conf 中的 IP 地址信息
        for node in "${nodes[@]}"; do
            newIP=$(wait_for_dns_lookup "$node" "$REDIS_DNS_RETRIES" 5)
            # The node can be new if we are updating the cluster, so catch the unbound variable error
            if [[ ${host_2_ip_array[$node]+true} ]]; then
                LOG_I "Changing old IP ${host_2_ip_array[$node]} by the new one ${newIP}"
                nodesFile=$(sed "s/${host_2_ip_array[$node]}/$newIP/g" "${APP_DATA_DIR}/nodes.conf")
                echo "$nodesFile" > "${APP_DATA_DIR}/nodes.conf"
            fi
            host_2_ip_array["$node"]="$newIP"
        done
        declare -p host_2_ip_array > "${APP_DATA_DIR}/nodes.sh"
    fi
}
