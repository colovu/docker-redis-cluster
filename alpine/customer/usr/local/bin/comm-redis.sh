#!/bin/bash
# Ver: 1.0 by Endial Fang (endial@126.com)
# 
# 应用通用业务处理函数

# 加载依赖脚本
. /usr/local/scripts/libcommon.sh       # 通用函数库

. /usr/local/scripts/libfile.sh
. /usr/local/scripts/libfs.sh
. /usr/local/scripts/libos.sh
. /usr/local/scripts/libnet.sh
. /usr/local/scripts/libservice.sh
. /usr/local/scripts/libvalidations.sh

# 函数列表

# 使用环境变量中以 "APP_CFG_" 开头的的全局变量更新配置文件中对应项（全小写，以"."分隔）
# 举例：
#   APP_CFG_LOG_DIRS 对应配置文件中的配置项：log.dirs
redis_configure_from_env_variables() {
    # Map environment variables to config properties
    for var in "${!APP_CFG_@}"; do
        key="$(echo "$var" | sed -e 's/^APP_CFG_//g' -e 's/_/\./g' | tr '[:upper:]' '[:lower:]')"
        value="${!var}"
        redis_conf_set "$key" "$value"
    done
}

# 将变量配置更新至配置文件
# 参数:
#   $1 - 文件
#   $2 - 变量
#   $3 - 值（列表）
redis_common_conf_set() {
    local file="${1:?missing file}"
    local key="${2:?missing key}"
    shift
    shift
    local values=("$@")

    if [[ "${#values[@]}" -eq 0 ]]; then
        LOG_E "missing value"
        return 1
    elif [[ "${#values[@]}" -ne 1 ]]; then
        for i in "${!values[@]}"; do
            redis_common_conf_set "$file" "${key[$i]}" "${values[$i]}"
        done
    else
        value="${values[0]}"
        # Sanitize inputs
        value="${value//\\/\\\\}"
        value="${value//&/\\&}"
        value="${value//\?/\\?}"
        [[ "$value" = "" ]] && value="\"$value\""
        # Check if the value was set before
        if grep -q "^[# ]*${key} .*" "$file"; then
            # Update the existing key
            replace_in_file "$file" "^[# ]*${key} .*" "${key} ${value}" false
        else
            # 增加一个新的配置项；如果在其他位置有类似操作，需要注意换行
            printf "\n%s %s" "$key" "$value" >>"$file"
        fi
    fi
}

# 获取配置文件中指定关键字对应的值
# 变量:
#   $1 - 变量
redis_conf_get() {
    local key="${1:?missing key}"

    grep -E "^\s*$key " "${REDIS_CONF_FILE}" | awk '{print $2}'
}

# 更新 redis.conf 配置文件中指定变量值，设置关键字及对应值
# 变量:
#   $1 - 变量
#   $2 - 值（列表）
redis_conf_set() {
    redis_common_conf_set "${REDIS_CONF_FILE}" "$@"
}

# 更新 sentinel.conf 配置文件中指定变量值，设置关键字及对应值
# 变量:
#   $1 - 变量
#   $2 - 值（列表）
redis_sentinel_conf_set() {
    redis_common_conf_set "${REDIS_SENTINEL_FILE}" "$@"
}

# 更新 redis.conf 配置文件中指定变量值，取消关键字设置信息
# 变量:
#   $1 - 变量
redis_conf_unset() {
    local key="${1:?missing key}"
    remove_in_file "${REDIS_CONF_FILE}" "^\s*$key .*" false
}

# 获取 Redis 版本信息
redis_version() {
    redis-cli --version | grep -E -o "[0-9]+.[0-9]+.[0-9]+"
}

# 获取 Redis 主版本号
redis_major_version() {
    redis_version | grep -E -o "^[0-9]+"
}

# 禁用 Redis 不安全的命令
# 参数:
#   $1 - 待禁用的命令列表
redis_disable_unsafe_commands() {
    # The current syntax gets a comma separated list of commands, we split them
    # before passing to redis_disable_unsafe_commands
    read -r -a disabledCommands <<< "$(tr ',' ' ' <<< "$REDIS_DISABLE_COMMANDS")"
    LOG_D "Disabling commands: ${disabledCommands[*]}"
    echo "" >> "${REDIS_CONF_FILE}"
    for cmd in "${disabledCommands[@]}"; do
        if grep -E -q "^\s*rename-command\s+$cmd\s+\"\"\s*$" "${REDIS_CONF_FILE}"; then
            LOG_D "$cmd was already disabled"
            continue
        fi
        echo "rename-command $cmd \"\"" >> "${REDIS_CONF_FILE}"
    done
}

# 生成默认配置文件
redis_generate_conf() {
    redis_conf_set port "$REDIS_PORT"
    redis_conf_set dir "${APP_DATA_DIR}"
    redis_conf_set logfile "${APP_LOG_DIR}/redis.log" # Log to stdout
    redis_conf_set pidfile "${REDIS_PID_FILE}"
    redis_conf_set daemonize no
    redis_conf_set bind 127.0.0.1 # disallow remote connections when init
    # Enable AOF https://redis.io/topics/persistence#append-only-file
    # Leave default fsync (every second)
    redis_conf_set appendonly "${REDIS_AOF_ENABLED}"
    # Disable RDB persistence, AOF persistence already enabled.
    # Ref: https://redis.io/topics/persistence#interactions-between-aof-and-rdb-persistence
    redis_conf_set save ""
    # TLS configuration
    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        if [[ "$REDIS_PORT" ==  "6379" ]] && [[ "$REDIS_TLS_PORT" ==  "6379" ]]; then
            # If both ports are set to default values, enable TLS traffic only
            redis_conf_set port 0
            redis_conf_set tls-port "$REDIS_TLS_PORT"
        else
            # Different ports were specified
            redis_conf_set port "$REDIS_PORT"
            redis_conf_set tls-port "$REDIS_TLS_PORT"
        fi
        redis_conf_set tls-cert-file "$REDIS_TLS_CERT_FILE"
        redis_conf_set tls-key-file "$REDIS_TLS_KEY_FILE"
        redis_conf_set tls-ca-cert-file "$REDIS_TLS_CA_FILE"
        [[ -n "$REDIS_TLS_DH_PARAMS_FILE" ]] && redis_conf_set tls-dh-params-file "$REDIS_TLS_DH_PARAMS_FILE"
        redis_conf_set tls-auth-clients "$REDIS_TLS_AUTH_CLIENTS"
    fi

    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis_conf_set requirepass "$REDIS_PASSWORD"
    else
        redis_conf_unset requirepass
    fi
    if [[ -n "$REDIS_DISABLE_COMMANDS" ]]; then
        redis_disable_unsafe_commands
    fi
}

# 配置 Redis 复制模式参数
# 参数:
#   $1 - 复制模式
redis_configure_replication() {
    LOG_I "Configuring replication mode..."

    redis_conf_set replica-announce-ip "$(get_machine_ip)"
    redis_conf_set replica-announce-port "$REDIS_MASTER_PORT_NUMBER"
    if [[ "$REDIS_REPLICATION_MODE" = "master" ]]; then
        if [[ -n "$REDIS_PASSWORD" ]]; then
            redis_conf_set masterauth "$REDIS_PASSWORD"
        fi
    elif [[ "$REDIS_REPLICATION_MODE" =~ ^(slave|replica)$ ]]; then
        if [[ -n "$REDIS_SENTINEL_HOST" ]]; then
            local sentinel_info_command
            if is_boolean_yes "$REDIS_TLS_ENABLED"; then
                sentinel_info_command="redis-cli -h ${REDIS_SENTINEL_HOST} -p ${REDIS_SENTINEL_PORT_NUMBER} --tls --cert ${REDIS_TLS_CERT_FILE} --key ${REDIS_TLS_KEY_FILE} --cacert ${REDIS_TLS_CA_FILE} sentinel get-master-addr-by-name ${REDIS_SENTINEL_MASTER_NAME}"
            else
                sentinel_info_command="redis-cli -h ${REDIS_SENTINEL_HOST} -p ${REDIS_SENTINEL_PORT_NUMBER} sentinel get-master-addr-by-name ${REDIS_SENTINEL_MASTER_NAME}"
            fi
            REDIS_SENTINEL_INFO=($($sentinel_info_command))
            REDIS_MASTER_HOST=${REDIS_SENTINEL_INFO[0]}
            REDIS_MASTER_PORT_NUMBER=${REDIS_SENTINEL_INFO[1]}
        fi
        LOG_I "Waitting for Redis Master ready..."
        redis_wait_service "${REDIS_MASTER_HOST}:${REDIS_MASTER_PORT_NUMBER}"
        [[ -n "$REDIS_MASTER_PASSWORD" ]] && redis_conf_set masterauth "$REDIS_MASTER_PASSWORD"
        # Starting with Redis 5, use 'replicaof' instead of 'slaveof'. Maintaining both for backward compatibility
        local parameter="replicaof"
        [[ $(redis_major_version) -lt 5 ]] && parameter="slaveof"
        redis_conf_set "$parameter" "$REDIS_MASTER_HOST $REDIS_MASTER_PORT_NUMBER"
        # Configure replicas to use TLS for outgoing connections to the master
        if is_boolean_yes "$REDIS_TLS_ENABLED"; then
            redis_conf_set tls-replication yes
        fi
    fi
}

# 检测用户参数信息是否满足条件; 针对部分权限过于开放情况，打印提示信息
redis_verify_minimum_env() {
    local error_code=0
    LOG_D "Validating settings in REDIS_* env vars..."

    print_validation_error() {
        LOG_E "$1"
        error_code=1
    }

    # Redis authentication validations
    if is_boolean_yes "$ALLOW_ANONYMOUS_LOGIN"; then
        LOG_W "You set the environment variable ALLOW_ANONYMOUS_LOGIN=${ALLOW_ANONYMOUS_LOGIN}. For safety reasons, do not use this flag in a production environment."
    elif [[ -z "$REDIS_PASSWORD" ]]; then
        print_validation_error "The REDIS_PASSWORD environment variable is empty or not set. Set the environment variable ALLOW_ANONYMOUS_LOGIN=yes to allow the container to be started with blank passwords. This is recommended only for development."
    fi

    if [[ -n "$REDIS_REPLICATION_MODE" ]]; then
        if [[ "$REDIS_REPLICATION_MODE" =~ ^(slave|replica)$ ]]; then
            if [[ -n "$REDIS_MASTER_PORT_NUMBER" ]]; then
                if ! err=$(validate_port "$REDIS_MASTER_PORT_NUMBER"); then
                    print_validation_error "An invalid port was specified in the environment variable REDIS_MASTER_PORT_NUMBER: $err"
                fi
            fi
            if ! is_boolean_yes "$ALLOW_ANONYMOUS_LOGIN" && [[ -z "$REDIS_MASTER_PASSWORD" ]]; then
                print_validation_error "The REDIS_MASTER_PASSWORD environment variable is empty or not set. Set the environment variable ALLOW_ANONYMOUS_LOGIN=yes to allow the container to be started with blank passwords. This is recommended only for development."
            fi
        elif [[ "$REDIS_REPLICATION_MODE" != "master" ]]; then
            print_validation_error "Invalid replication mode. Available options are 'master/replica'"
        fi
    fi

    if is_boolean_yes "$REDIS_TLS_ENABLED"; then
        if [[ "$REDIS_PORT" == "$REDIS_TLS_PORT" ]] && [[ "$REDIS_PORT" != "6379" ]]; then
            # If both ports are assigned the same numbers and they are different to the default settings
            print_validation_error "Enviroment variables REDIS_PORT and REDIS_TLS_PORT point to the same port number (${REDIS_PORT}). Change one of them or disable non-TLS traffic by setting REDIS_PORT=0"
        fi
        if [[ -z "$REDIS_TLS_CERT_FILE" ]]; then
            print_validation_error "You must provide a X.509 certificate in order to use TLS"
        elif [[ ! -f "$REDIS_TLS_CERT_FILE" ]]; then
            print_validation_error "The X.509 certificate file in the specified path ${REDIS_TLS_CERT_FILE} does not exist"
        fi
        if [[ -z "$REDIS_TLS_KEY_FILE" ]]; then
            print_validation_error "You must provide a private key in order to use TLS"
        elif [[ ! -f "$REDIS_TLS_KEY_FILE" ]]; then
            print_validation_error "The private key file in the specified path ${REDIS_TLS_KEY_FILE} does not exist"
        fi
        if [[ -z "$REDIS_TLS_CA_FILE" ]]; then
            print_validation_error "You must provide a CA X.509 certificate in order to use TLS"
        elif [[ ! -f "$REDIS_TLS_CA_FILE" ]]; then
            print_validation_error "The CA X.509 certificate file in the specified path ${REDIS_TLS_CA_FILE} does not exist"
        fi
        if [[ -n "$REDIS_TLS_DH_PARAMS_FILE" ]] && [[ ! -f "$REDIS_TLS_DH_PARAMS_FILE" ]]; then
            print_validation_error "The DH param file in the specified path ${REDIS_TLS_DH_PARAMS_FILE} does not exist"
        fi
    fi

    [[ "$error_code" -eq 0 ]] || exit "$error_code"
}

# 更改默认监听地址为 "*" 或 "0.0.0.0"，以对容器外提供服务；默认配置文件应当为仅监听 localhost(127.0.0.1)
redis_enable_remote_connections() {
    LOG_D "Modify default config to enable all IP access"

    redis_conf_set daemonize no
    redis_conf_set bind 0.0.0.0 # Allow remote connections
}

# 检测依赖的服务端口是否就绪；该脚本依赖系统工具 'netcat'
# 参数:
#   $1 - host:port
redis_wait_service() {
    local serviceport=${1:?Missing server info}
    local service=${serviceport%%:*}
    local port=${serviceport#*:}
    local retry_seconds=5
    local max_try=100
    let i=1

    if [[ -z "$(which nc)" ]]; then
        LOG_E "Nedd nc installed before, command: \"apt-get install netcat\"."
        exit 1
    fi

    LOG_I "[0/${max_try}] check for ${service}:${port}..."

    set +e
    nc -z ${service} ${port}
    result=$?

    until [ $result -eq 0 ]; do
      LOG_D "  [$i/${max_try}] not available yet"
      if (( $i == ${max_try} )); then
        LOG_E "${service}:${port} is still not available; giving up after ${max_try} tries."
        exit 1
      fi
      
      LOG_I "[$i/${max_try}] try in ${retry_seconds}s once again ..."
      let "i++"
      sleep ${retry_seconds}

      nc -z ${service} ${port}
      result=$?
    done

    set -e
    LOG_I "[$i/${max_try}] ${service}:${port} is available."
}

# 以后台方式启动应用服务，并等待启动就绪
redis_start_server_bg() {
    redis_is_server_running && return

    LOG_I "Starting ${APP_NAME} in background..."

    if is_boolean_yes "${ENV_DEBUG}"; then
        "redis-server" "${REDIS_CONF_FILE}" "--daemonize" "yes"
    else
        "redis-server" "${REDIS_CONF_FILE}" "--daemonize" "yes" >/dev/null 2>&1
    fi

    local counter=3
    while ! redis_is_server_running ; do
        if [[ "$counter" -ne 0 ]]; then
            break
        fi
        sleep 1;
        counter=$((counter - 1))
    done

	# 通过命令或特定端口检测应用是否就绪
    LOG_I "Checking ${APP_NAME} ready status..."
    #wait-for-port --timeout 60 "$REDIS_PORT"

    LOG_D "${APP_NAME} is ready for service..."
}

# 停止应用服务
redis_stop_server() {
    redis_is_server_running || return

    local pass
    local port
    local args
    LOG_I "Stopping ${APP_NAME}..."

    pass="$(redis_conf_get "requirepass")"
    is_boolean_yes "$REDIS_TLS_ENABLED" && port="$(redis_conf_get "tls-port")" || port="$(redis_conf_get "port")"

    [[ -n "$pass" ]] && args+=("-a" "\"$pass\"")
    [[ "$port" != "0" ]] && args+=("-p" "$port")
    #args+=("--daemonize" "yes")

    if is_boolean_yes "${ENV_DEBUG}"; then
        "redis-cli" "${args[@]}" shutdown
    else
        "redis-cli" "${args[@]}" shutdown >/dev/null 2>&1
    fi

	# 检测停止是否完成
    local counter=5
    while [[ "$counter" -ne 0 ]] && is_app_server_running; do
        LOG_D "Waiting for ${APP_NAME} to stop..."
        sleep 1
        counter=$((counter - 1))
    done
}

# 检测应用服务是否在后台运行中
redis_is_server_running() {
    LOG_D "Check if ${APP_NAME} is running..."
    local pid
    pid="$(get_pid_from_file "${REDIS_PID_FILE}")"

    if [[ -z "${pid}" ]]; then
        false
    else
        is_service_running "${pid}"
    fi
}

# 清理初始化应用时生成的临时文件
redis_clean_tmp_file() {
    LOG_D "Clean ${APP_NAME} tmp files for init..."

}

# 在重新启动容器时，删除标志文件及必须删除的临时文件 (容器重新启动)
redis_clean_from_restart() {
    LOG_D "Clean ${APP_NAME} tmp files for restart..."
    local -r -a files=(
        "${REDIS_PID_FILE}"
    )

    for file in ${files[@]}; do
        if [[ -f "$file" ]]; then
            LOG_I "Cleaning stale $file file"
            rm "$file"
        fi
    done
}

# 应用默认初始化操作
# 执行完毕后，生成文件 ${APP_CONF_DIR}/.app_init_flag 及 ${APP_DATA_DIR}/.data_init_flag 文件
redis_default_init() {
	redis_clean_from_restart
    LOG_D "Check init status of ${APP_NAME}..."

    # 检测配置文件是否存在
    if [[ ! -f "${APP_CONF_DIR}/.app_init_flag" ]]; then
        LOG_I "No injected configuration file found, creating default config files..."
        redis_generate_conf

        # Configure Replication mode
        if [[ -n "$REDIS_REPLICATION_MODE" ]]; then
            redis_configure_replication
        fi

        touch "${APP_CONF_DIR}/.app_init_flag"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> "${APP_CONF_DIR}/.app_init_flag"
    else
        LOG_I "User injected custom configuration detected!"
    fi

    if [[ ! -f "${APP_DATA_DIR}/.data_init_flag" ]]; then
        LOG_I "Deploying ${APP_NAME} from scratch..."

		# 启动后台服务
        #redis_start_server_bg


        touch ${APP_DATA_DIR}/.data_init_flag
        echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_DATA_DIR}/.data_init_flag
    else
        LOG_I "Deploying ${APP_NAME} with persisted data..."
    fi
}

# 用户自定义的前置初始化操作，依次执行目录 preinitdb.d 中的初始化脚本
# 执行完毕后，生成文件 ${APP_DATA_DIR}/.custom_preinit_flag
redis_custom_preinit() {
    LOG_I "Check custom pre-init status of ${APP_NAME}..."

    # 检测用户配置文件目录是否存在 preinitdb.d 文件夹，如果存在，尝试执行目录中的初始化脚本
    if [ -d "/srv/conf/${APP_NAME}/preinitdb.d" ]; then
        # 检测数据存储目录是否存在已初始化标志文件；如果不存在，检索可执行脚本文件并进行初始化操作
        if [[ -n $(find "/srv/conf/${APP_NAME}/preinitdb.d/" -type f -regex ".*\.\(sh\)") ]] && \
            [[ ! -f "${APP_DATA_DIR}/.custom_preinit_flag" ]]; then
            LOG_I "Process custom pre-init scripts from /srv/conf/${APP_NAME}/preinitdb.d..."

            # 检索所有可执行脚本，排序后执行
            find "/srv/conf/${APP_NAME}/preinitdb.d/" -type f -regex ".*\.\(sh\)" | sort | process_init_files

            touch "${APP_DATA_DIR}/.custom_preinit_flag"
            echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> "${APP_DATA_DIR}/.custom_preinit_flag"
            LOG_I "Custom preinit for ${APP_NAME} complete."
        else
            LOG_I "Custom preinit for ${APP_NAME} already done before, skipping initialization."
        fi
    fi

    # 检测依赖的服务是否就绪
    #for i in ${SERVICE_PRECONDITION[@]}; do
    #    redis_wait_service "${i}"
    #done
}

# 用户自定义的应用初始化操作，依次执行目录initdb.d中的初始化脚本
# 执行完毕后，生成文件 ${APP_DATA_DIR}/.custom_init_flag
redis_custom_init() {
    LOG_I "Check custom initdb status of ${APP_NAME}..."

    # 检测用户配置文件目录是否存在 initdb.d 文件夹，如果存在，尝试执行目录中的初始化脚本
    if [ -d "/srv/conf/${APP_NAME}/initdb.d" ]; then
    	# 检测数据存储目录是否存在已初始化标志文件；如果不存在，检索可执行脚本文件并进行初始化操作
    	if [[ -n $(find "/srv/conf/${APP_NAME}/initdb.d/" -type f -regex ".*\.\(sh\|sql\|sql.gz\)") ]] && \
            [[ ! -f "${APP_DATA_DIR}/.custom_init_flag" ]]; then
            LOG_I "Process custom init scripts from /srv/conf/${APP_NAME}/initdb.d..."

            # 启动后台服务
            #redis_start_server_bg

            # 检索所有可执行脚本，排序后执行
    		find "/srv/conf/${APP_NAME}/initdb.d/" -type f -regex ".*\.\(sh\|sql\|sql.gz\)" | sort | while read -r f; do
                case "$f" in
                    *.sh)
                        if [[ -x "$f" ]]; then
                            LOG_D "Executing $f"; "$f"
                        else
                            LOG_D "Sourcing $f"; . "$f"
                        fi
                        ;;
                    *.sql)    
                        LOG_D "Executing $f"; 
                        postgresql_execute "${PG_DATABASE}" "${PG_INITSCRIPTS_USERNAME}" "${PG_INITSCRIPTS_PASSWORD}" < "$f"
                        ;;
                    *.sql.gz) 
                        LOG_D "Executing $f"; 
                        gunzip -c "$f" | postgresql_execute "${PG_DATABASE}" "${PG_INITSCRIPTS_USERNAME}" "${PG_INITSCRIPTS_PASSWORD}"
                        ;;
                    *)        
                        LOG_D "Ignoring $f" ;;
                esac
            done

            touch "${APP_DATA_DIR}/.custom_init_flag"
    		echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> "${APP_DATA_DIR}/.custom_init_flag"
    		LOG_I "Custom init for ${APP_NAME} complete."
    	else
    		LOG_I "Custom init for ${APP_NAME} already done before, skipping initialization."
    	fi
    fi

    # 检测服务是否运行中；如果运行，则停止后台服务
	redis_is_server_running && redis_stop_server

    # 删除第一次运行生成的临时文件
    redis_clean_tmp_file

	# 绑定所有 IP ，启用远程访问
    redis_enable_remote_connections
}

