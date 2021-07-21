# Redis

针对 [Redis](https://redis.io) 应用的 Docker 镜像，用于提供 Redis 服务。

详细信息可参照：[官方说明](https://redis.io/documentation)



<img src="img/redis-white.png" alt="redis-white" style="zoom:150%;" />

**版本信息：**

- 6.0、latest
- 5.0

**镜像信息：**

* 镜像地址：registry.cn-shenzhen.aliyuncs.com/colovu/redis-cluster:6.0



## TL;DR

Docker 快速启动命令：

```shell
$ docker run -d -e ALLOW_ANONYMOUS_LOGIN=yes registry.cn-shenzhen.aliyuncs.com/colovu/redis-cluster:6.0
```

Docker-Compose 快速启动命令：

```shell
$ curl -sSL https://raw.githubusercontent.com/colovu/docker-redis/master/docker-compose.yml > docker-compose.yml

$ docker-compose up -d
```

Docker-Compose 主从集群快速启动命令：

```shell
$ curl -sSL https://raw.githubusercontent.com/colovu/docker-redis/master/docker-compose-cluster.yml > docker-compose.yml

$ docker-compose -f docker-compose-cluster.yml up -d
```



---



## 默认对外声明

### 端口

- 6379：Redis 业务客户端访问端口
- 26379：Redis Sentinel 端口

### 数据卷

镜像默认提供以下数据卷定义，默认数据分别存储在自动生成的应用名对应`redis`子目录中：

```shell
/srv/data           # Redis 数据文件，主要存放Redis持久化数据；自动创建子目录redis
/srv/datalog	    # Redis 数据操作日志文件；自动创建子目录redis
/srv/conf           # Redis 配置文件；自动创建子目录redis
/var/log            # 日志文件，日志文件名为：redis.log
/var/run            # 进程运行PID文件，PID文件名为：redis_6379.pid、redis_sentinel.pid
```

如果需要持久化存储相应数据，需要**在宿主机建立本地目录**，并在使用镜像初始化容器时进行映射。宿主机相关的目录中如果不存在对应应用 Redis 的子目录或相应数据文件，则容器会在初始化时创建相应目录及文件。



## 容器配置

在初始化 Redis 容器时，如果没有预置配置文件，可以在命令行中设置相应环境变量对默认参数进行修改。类似命令如下：

```shell
$ docker run -d -e "REDIS_AOF_ENABLED=no" colovu/redis
```



### 常规配置参数

常使用的环境变量主要包括：

- **ALLOW_ANONYMOUS_LOGIN**：默认值：**no**。设置是否允许无密码连接。如果没有设置`REDIS_PASSWORD`，则必须设置当前环境变量为 `yes`
- **REDIS_PASSWORD**：默认值：**无**。客户端认证的密码
- **REDIS_DISABLE_COMMANDS**：默认值：**无**。设置禁用的 Redis 命令
- **REDIS_AOF_ENABLED**：默认值：**yes**。设置是否启用 Append Only File 存储

### 可选配置参数

如果没有必要，可选配置参数可以不用定义，直接使用对应的默认值，主要包括：

- **ENV_DEBUG**：默认值：**false**。设置是否输出容器调试信息。可设置为：1、true、yes
- **REDIS_PORT**：默认值：**6379**。设置应用的默认客户访问端口
- **REDIS_PASSWORD_FILE**：默认值：**无**。以绝对地址指定的客户端认证用户密码存储文件。该路径指的是容器内的路径
- **REDIS_MASTER_PASSWORD_FILE**：默认值：**无**。以绝对地址指定的服务器密码存储文件。该路径指的是容器内的路径

### Sentinel配置参数

- **REDIS_SENTINEL_HOST**：默认值：**无**
- **REDIS_SENTINEL_MASTER_NAME**：默认值：**无**
- **REDIS_SENTINEL_PORT_NUMBER**：默认值：**26379**。设置 Sentinel 默认端口

### 集群配置参数

使用 Redis 镜像，可以很容易的建立一个 [redis](https://redis.apache.org/doc/r3.1.2/redisAdmin.html) 集群。针对 redis 的集群模式（复制模式），有以下参数可以配置：

- **REDIS_REPLICATION_MOD**：默认值：**无**。当前主机在集群中的工作模式，可使用值为：`master`/`slave`/`replica`
- **REDIS_MASTER_HOST**：默认值：**无**。作为`slave`/`replica`时，对应的 master 主机名或 IP 地址
- **REDIS_MASTER_PORT_NUMBER**：默认值：**6379**。master 主机对应的端口
- **REDIS_MASTER_PASSWORD**：默认值：**无**。master 主机对应的登录验证密码

### TLS配置参数

使用证书加密传输时，相关配置参数如下：

- **REDIS_TLS_ENABLED**：启用或禁用 TLS。默认值：**no**
- **REDIS_TLS_PORT**：使用 TLS 加密传输的端口。默认值：**6379**
- **REDIS_TLS_CERT_FILE**：TLS 证书文件。默认值：**无**
- **REDIS_TLS_KEY_FILE**：TLS 私钥文件。默认值：**无**
- **REDIS_TLS_CA_FILE**：TLS 根证书文件。默认值：**无**
- **REDIS_TLS_DH_PARAMS_FILE**：包含 DH 参数的配置文件 (DH 加密方式时需要)。默认值：**无**
- **REDIS_TLS_AUTH_CLIENTS**：配置客户端是否需要 TLS 认证。 默认值：**yes**

当使用 TLS 时，则默认的 non-TLS 通讯被禁用。如果需要同时支持 TLS 与 non-TLS 通讯，可以使用参数`REDIS_TLS_PORT`配置容器使用不同的 TLS 端口。



## 安全

### 用户及密码

Redis 镜像默认禁用了无密码访问功能，在实际生产环境中建议使用用户名及密码控制访问；如果为了测试需要，可以使用以下环境变量启用无密码访问功能：

```shell
ALLOW_ANONYMOUS_LOGIN=yes
```

通过配置环境变量`REDIS_PASSWORD`，可以启用基于密码的用户认证功能。命令行使用参考：

```shell
$ docker run -d -e REDIS_PASSWORD=colovu colovu/redis
```

使用 Docker-Compose 时，`docker-compose.yml`应包含类似如下配置：

```yaml
services:
  redis:
  ...
    environment:
      - REDIS_PASSWORD=colovu
  ...
```

### 容器安全

本容器默认使用应用对应的运行时用户及用户组运行应用，以加强容器的安全性。在使用非`root`用户运行容器时，相关的资源访问会受限；应用仅能操作镜像创建时指定的路径及数据。使用`Non-root`方式的容器，更适合在生产环境中使用。



## 注意事项

- 容器中 Redis 启动参数不能配置为后台运行，只能使用前台运行方式，即：`daemonize no`


## 历史记录

- 2020.9.11：更新 Redis 版本为 6.0.8


----

本文原始来源 [Endial Fang](https://github.com/colovu) @ [Github.com](https://github.com)

