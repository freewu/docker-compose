# Nacos

Nacos（Dynamic Naming and Configuration Service）是阿里巴巴开源的服务注册中心 + 配置中心。

本目录为**单机版（standalone）+ 内嵌 Derby 存储**，不依赖外部数据库，直接 `docker compose up -d` 即可用。

| 项目 | 说明 |
|------|------|
| 镜像 | `nacos/nacos-server`（控制台与服务端是**同一个**镜像） |
| 版本 | `.env` 中的 `NACOS_VERSION`，默认 `v3.2.4`（3.x） |
| 默认账号 | `nacos` / `123456`（用户名固定为 `nacos`，密码由 `.env` 提供） |
| 数据目录 | `/data/nacos/data`（Derby 数据库，删掉等于恢复出厂） |
| 容器名 | `nacos`、`nacos-init` |

## 使用到的端口

| 端口 | 协议 | 用途 | 从宿主机访问 |
|------|------|------|-------------|
| **8080** | HTTP | 控制台 UI（Nacos **3.x** 起控制台独立成这个端口） | <http://localhost:8080/> |
| **8848** | HTTP | 服务端 API / OpenAPI / 登录接口（`contextPath=/nacos`） | <http://localhost:8848/nacos> |
| **9848** | gRPC | SDK 客户端连接端口（= 8848 + 1000） | 应用里配 `server-addr=<IP>:8848` |
| 9849 | gRPC | 集群内部 gRPC（= 8848 + 1001） | 单机模式用不到，**不映射**，只在容器内监听 |
| 7848 | TCP | Raft 端口（= 8848 - 1000） | 单机模式用不到，**不映射**，只在容器内监听 |

> 8080 / 8848 / 9848 在本仓库其它服务中都没有使用，不会与已有目录冲突。
>
> 注意端口偏移关系：**9848 = 8848 + 1000**、9849 = 8848 + 1001、7848 = 8848 - 1000。
> 如果要换 8848 的端口，要么保持 `宿主机端口:容器端口` 一一对应，要么把 9848 也按 `容器9848` 映射到对应宿主机端口，否则客户端连不上。

## 数据目录（宿主机）

| 宿主机路径 | 容器内路径 | 内容 |
|-----------|-----------|------|
| `/data/nacos/data` | `/home/nacos/data` | 内嵌 Derby 数据库：配置、服务列表、用户、权限等**全部数据** |
| `/data/nacos/logs` | `/home/nacos/logs` | 日志（`nacos.log`、`naming-server.log`、`access_log` 等） |

清空数据（恢复出厂，数据会丢）：

```bash
docker compose down && rm -rf /data/nacos/data/* && docker compose up -d
```

## 账号密码等外部配置（.env）

| 变量 | 必填 | 说明 |
|------|:---:|------|
| `NACOS_VERSION` | | 镜像版本，升级只改这一处 |
| `NACOS_ADMIN_PASSWORD` | ✅ | 控制台管理员 `nacos` 的密码（上限 72 字符），容器启动时由 `nacos-init` 写入 |
| `NACOS_AUTH_ENABLE` | | Client API（应用的注册/配置/发现请求）是否需要 `accessToken`，默认 `true` |
| `NACOS_AUTH_ADMIN_ENABLE` | | 管理端 API 是否需要鉴权，默认 `true` |
| `NACOS_AUTH_CONSOLE_ENABLE` | | 控制台是否需要登录，默认 `true` |
| `NACOS_AUTH_TOKEN` | ✅ | JWT 签名密钥，**必须是 Base64**，解码后至少 32 字节（`openssl rand -base64 48`） |
| `NACOS_AUTH_IDENTITY_KEY` / `NACOS_AUTH_IDENTITY_VALUE` | ✅ | 服务端身份标识（服务间/集群调用校验用），改成自己的随机串 |
| `NACOS_JVM_XMS` / `NACOS_JVM_XMX` / `NACOS_JVM_XMN` | | JVM 内存，不填用镜像默认 `1g/1g/512m` |
| `NACOS_SERVER_IP` | | 可选，Nacos 通告给客户端的地址（见常见问题 3） |

> 管理员用户名固定是 `nacos`：Nacos 3.x 的初始化接口只能创建这个用户名，所以没有用户名配置项；
> 需要别的账号，登录控制台后在【用户管理】里新建即可。

改完 `.env` 后重建生效：

```bash
docker compose up -d --force-recreate nacos nacos-init
```

## 启动

```bash
cd nacos
docker compose up -d

docker compose ps            # nacos 应为 healthy；nacos-init 显示 Exited (0) 是正常现象（一次性任务）
docker compose logs -f nacos-init
```

启动顺序：`nacos`（等它 healthy）→ `nacos-init`（用 `.env` 里的密码初始化管理员，然后退出）。

## 验证

浏览器打开控制台 <http://localhost:8080/>，用 `nacos` / `.env` 中的密码登录。

```bash
# 1. 健康检查（未鉴权接口，就绪前返回 500）
curl http://localhost:8080/v3/console/health/readiness

# 2. 登录拿 accessToken
curl -X POST 'http://localhost:8848/nacos/v3/auth/user/login' \
     -d 'username=nacos' -d 'password=123456'

# 3. 服务注册 / 服务发现 / 发布配置（$TOKEN 换成上一步返回值里的 accessToken；IP 换成宿主机局域网 IP）
curl -X POST 'http://localhost:8848/nacos/v3/client/ns/instance?serviceName=quickstart.test.service&ip=192.168.0.200&port=8080' \
     -H "accessToken:$TOKEN"
curl -X GET 'http://localhost:8848/nacos/v3/client/ns/instance/list?serviceName=quickstart.test.service' \
     -H "accessToken:$TOKEN"
curl -X POST 'http://localhost:8848/nacos/v3/client/cs/config?dataId=quickstart.test&groupName=DEFAULT_GROUP&content=hello' \
     -H "accessToken:$TOKEN"
```

## 常见问题

### 1. 打开控制台要求"初始化管理员账号"

正常情况下 `nacos-init` 容器已经用 `.env` 里的密码建好了，不需要手动初始化。
如果它失败了（`docker compose logs nacos-init`），也可以手动调接口创建（**只在还没有管理员时可用**，已存在会返回 409）：

```bash
curl -X POST 'http://localhost:8848/nacos/v3/auth/user/admin?password=123456'
```

### 2. 改了 `.env` 里的密码不生效 / 忘记管理员密码

Nacos 的管理员密码存在数据库里，**没有环境变量可以覆盖**。`nacos-init` 只在"还没有管理员"时创建，已存在时不会覆盖（保证幂等），所以：

1. 把 `.env` 的 `NACOS_ADMIN_PASSWORD` 改成控制台**当前真实密码**（让校验通过）；
2. 或者登录控制台后在【用户管理】里改密码，再同步修改 `.env`；
3. 或者清空数据重建（数据会丢）：`docker compose down && rm -rf /data/nacos/data/* && docker compose up -d`。

### 3. 宿主机上的应用连不上 Nacos（gRPC 9848）

Nacos 会把**自己认为的地址**通告给客户端，客户端再用它连 9848：

* 应用也跑在 Docker 里 → 把应用接入本目录的网络（`docker network connect nacos-net <容器>`，或在本目录 compose 里加服务），用 `server-addr=nacos:8848`；
* 应用跑在宿主机上（Windows/Mac 的 Docker Desktop）→ 容器主机名/容器 IP 都不可达，此时在 `.env` 里设置
  `NACOS_SERVER_IP=<宿主机局域网 IP>`（如 `192.168.0.200`）后重建，Nacos 就会通告宿主机 IP，客户端走映射出去的 8848/9848 端口。

### 4. 接口返回 403 / `user not found!` / `authorization failed`

`NACOS_AUTH_ENABLE=true`（默认）时，Client API 需要带 `accessToken` 请求头：先调 `/nacos/v3/auth/user/login` 拿 token。
如果本机调试嫌麻烦，把 `.env` 里的 `NACOS_AUTH_ENABLE` 改成 `false` 后重建容器即可（控制台登录不受影响）。

### 5. 端口被占用怎么改

改 `docker-compose.yml` 里 `ports` 的**左边**（宿主机侧），容器内端口保持不变，例如控制台换成 `8880:8080`。
只有 8848 需要连带改 9848（见上面"端口偏移关系"），8080 可以独立改。

### 6. 内存占用高

镜像默认 JVM 是 `-Xms1g -Xmx1g -Xmn512m`。机器内存紧张时在 `.env` 里打开注释改成 `512m/512m/256m`：

```dotenv
NACOS_JVM_XMS=512m
NACOS_JVM_XMX=512m
NACOS_JVM_XMN=256m
```

### 7. 想改用 MySQL 存元数据

本目录用的是内嵌 Derby（够单机开发用）。要换 MySQL：先在 MySQL 里建库并导入 Nacos 发行包中的 `mysql-schema.sql`，
再给 `nacos` 服务加环境变量 `SPRING_DATASOURCE_PLATFORM=mysql`、`MYSQL_SERVICE_HOST`、`MYSQL_SERVICE_DB_NAME`、
`MYSQL_SERVICE_USER`、`MYSQL_SERVICE_PASSWORD`、`MYSQL_SERVICE_DB_PARAM`（参考 [nacos-docker](https://github.com/nacos-group/nacos-docker) 的 `standalone-mysql.yaml`）。

### 8. 想用 2.x 老版本

把 `.env` 的 `NACOS_VERSION` 换成 `v2.5.1` 之类的 2.x 版本即可，但注意 2.x 的**控制台在 8848**（`http://localhost:8848/nacos`），
没有独立的 8080 端口，可自行删掉 `8080:8080` 这行；另外 2.x 与 3.x 的登录接口路径不同（2.x 是 `/nacos/v1/auth/login`）。
