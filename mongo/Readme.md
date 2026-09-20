# MongoDB

MongoDB 单机版（文档数据库 / NoSQL），用于本地开发调试。

| 项目 | 说明 |
|------|------|
| 镜像 | `mongo`（版本见 `.env` 的 `MONGO_VERSION`，默认 `8.0` LTS，即 8.0.32；当前 latest 是 8.3.11） |
| 容器名 | `mongo` |
| 启动方式 | `mongod --config /etc/mongo/mongod.conf --auth`（`--auth` 是镜像入口脚本根据 `.env` 里的 `MONGO_INITDB_ROOT_*` 自动加的）；默认**单机模式**，多文档事务需自己开副本集，见「单节点副本集」 |
| 连接串 | `mongodb://root:123456@192.168.110.141:27017/?authSource=admin` |
| 数据目录 | `/data/mongodb/data/db`（数据，容器内 `/data/db`） |
| 日志目录 | `/data/mongodb/data/log`（容器内 `/var/log/mongodb`，日志文件 `mongod.log`） |
| 配置文件 | `./config/mongod.conf` → `/etc/mongo/mongod.conf` |
| 初始化脚本 | `./script/init.sh` → `/docker-entrypoint-initdb.d/init.sh`（只在首次初始化时执行一次） |
| 目录结构 | `.env` + `docker-compose.yml` + `config/mongod.conf` + `script/init.sh` + `Readme.md` |

> 默认账号（都只在**首次初始化**即数据目录为空时创建，之后改 `.env` 不会变，见常见问题 5）：
>
> | 账号 | 密码 | 库 | 权限 | 谁建的 |
> |------|------|----|------|--------|
> | `root` | `123456` | `admin` | `root`（超级管理员） | 镜像按 `.env` 里的 `MONGO_INITDB_ROOT_*` 创建 |
> | `test` | `123456` | `hi` | `readWrite`（只读写 `hi`） | `script/init.sh` |
>
> 默认是**单机模式 + 鉴权**（standalone，够本地开发用）。要用**多文档事务**（Spring `@Transactional`、`session.startTransaction()`）
> 就按下面「单节点副本集」开启 —— 注意「鉴权 + 副本集」必须同时配 `security.keyFile`，否则 mongod 直接启动失败（见常见问题 16）。

> **内核 6.19 ~ 7.0.13 的机器注意**：官方镜像自带的 `GLIBC_TUNABLES=glibc.pthread.rseq=0` 在这段内核上会让
> mongod 直接退出，日志是 `MongoDB cannot start: Linux kernel versions 6.19 and newer has a known incompatibility...`。
> 这不是本目录配置写错了 —— compose 里已经把 `GLIBC_TUNABLES` 默认覆盖成 `glibc.pthread.rseq=1` 绕开它，
> 内核自查 `uname -r`，完整对照表和其它做法见「常见问题 14」。

## 使用到的端口

宿主机映射的端口（和容器内一致，1:1）：

| 端口 | 容器内 | 协议 | 用途 | 访问地址 / 说明 |
|------|:---:|------|------|-----------------|
| **27017** | 27017 | TCP | MongoDB 协议 | `mongodb://192.168.110.141:27017`；本仓库只有 mongo 用 27017，不冲突 |

容器内不监听、本目录也不用的端口：27018 / 27019（副本集其它成员 / 分片用）、27020（mongos 默认端口），按需自己加映射。

端口占用自查：

- `27017` 在本仓库其它服务里没有用到（`elastic-search` 的 9200、`redis` 的 6379、`postgre` 的 5432 都是别的端口）；
- 如果你本机装了原生 MongoDB，先确认没占 27017：`ss -lntp | grep 27017`。

## 启动

```bash
cd mongo
docker compose up -d
docker compose ps                  # 等 STATUS 出现 (healthy)；首次启动要初始化数据目录，约 10~30 秒
docker compose logs -f mongo       # 看到 "MongoDB init process complete; ready for start up" + "Waiting for connections" 即成功
```

宿主机确认端口在监听：

```bash
ss -lntp | grep 27017
```

日志（mongod 自己的日志是写文件的，不走 `docker logs`）：

```bash
tail -f /data/mongodb/data/log/mongod.log
```

## 验证

```bash
# 1. 管理员 ping（不用鉴权库名容易踩坑，一定要带 --authenticationDatabase admin）
docker exec -it mongo mongosh -u root -p 123456 --authenticationDatabase admin \
  --eval 'db.adminCommand({ ping: 1 })'

# 2. 应用账号读写 hi 库（init.sh 建的账号）
docker exec -it mongo mongosh "mongodb://test:123456@127.0.0.1:27017/hi?authSource=hi" \
  --eval 'db.demo.insertOne({ hello: "mongo", t: new Date() }); printjson(db.demo.findOne())'

# 3. 看有哪些库 / 当前连接信息
docker exec -it mongo mongosh -u root -p 123456 --authenticationDatabase admin \
  --eval 'db.adminCommand({ listDatabases: 1 }).databases.forEach(d => print(d.name))'

# 4. 交互式进容器（退出：exit）
docker exec -it mongo mongosh -u root -p 123456 --authenticationDatabase admin
```

## 单节点副本集（可选，多文档事务才需要）

默认**不开**副本集（单机模式）。因为本目录开了鉴权（`.env` 里的 `MONGO_INITDB_ROOT_*` 会让镜像入口脚本
给 mongod 自动追加 `--auth`），而 MongoDB 要求「**鉴权 + 副本集**」必须配内部认证（keyFile），否则直接启动失败
（`BadValue: security.keyFile is required ...`，见常见问题 16）。要用多文档事务就按下面三步开。

### 1. 生成 keyFile（放命名卷里）

keyFile 的内容只要 6~1024 字节随机数据，但 **权限必须是 400/600**，否则 mongod 拒绝启动
（`InvalidPath: permissions on ... are too open`）。所以放 Docker 命名卷（Linux 文件系统，权限改得动）；
放宿主机目录后在 Windows / macOS 上权限往往改不动（始终 777），就会踩这个坑。

```bash
cd mongo
docker volume create mongo-key >/dev/null
docker run --rm -v mongo-key:/key alpine \
  sh -c 'head -c 700 /dev/urandom | base64 > /key/keyfile && chmod 400 /key/keyfile && chown 999:999 /key/keyfile'
docker run --rm -v mongo-key:/key alpine ls -l /key/keyfile     # 应是 -r-------- 999 999
```

### 2. 打开配置里注释掉的三处（都在本目录下）

```yaml
# config/mongod.conf：取消注释这两段
replication:
  oplogSizeMB: 51200
  replSetName: rs0
security:
  keyFile: /etc/mongo-key/keyfile

# docker-compose.yml：services.mongo.volumes 里取消注释
      - mongo-key:/etc/mongo-key
# docker-compose.yml：文件末尾取消注释
volumes:
  mongo-key:
    name: mongo-key        # 固定卷名，和上面 docker run 用的名字一致
```

改完重建容器（配置和挂载变了，`restart` 不会重新读挂载）：

```bash
docker compose up -d --force-recreate
docker compose logs --tail=5 mongo        # 看到 "Waiting for connections" 就起来了
```

### 3. 初始化副本集（只需一次）

成员 host **要写宿主机局域网 IP**，写 `127.0.0.1` / 容器名的话，别的机器连上来会拿到一个连不通的地址：

```bash
docker exec -it mongo mongosh -u root -p 123456 --authenticationDatabase admin --eval '
  rs.initiate({
    _id: "rs0",
    members: [{ _id: 0, host: "192.168.110.141:27017" }]
  })
'
# 等几秒变 PRIMARY
docker exec -it mongo mongosh -u root -p 123456 --authenticationDatabase admin --eval 'rs.status().members'
```

初始化后，需要副本集语义的客户端在连接串里加上 `replicaSet=rs0`：

```
mongodb://root:123456@192.168.110.141:27017/?authSource=admin&replicaSet=rs0
```

> 要退回单机模式：把上面三处改回注释、`docker compose up -d --force-recreate` 即可。
> 如果已经 `rs.initiate()` 过，建议清空数据目录重启（常见问题 11）——副本集初始化过的数据目录
> （`local` 库里存了副本集配置）直接当单机起会报错，别拿同一份目录在「单机 / 副本集」之间来回切。

## `.env` 配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MONGO_VERSION` | `8.0` | 镜像 tag，固定大版本（`8.0` = LTS / `8.3` = 最新 / `7.0` = 上一代 LTS） |
| `MONGO_GLIBC_TUNABLES` | `glibc.pthread.rseq=1` | 容器里的 `GLIBC_TUNABLES`，绕开内核 6.19 ~ 7.0.13 的启动检查；内核 < 6.19 或 ≥ 7.0.14 可改回 `glibc.pthread.rseq=0`，见常见问题 14 |
| `MONGO_INITDB_ROOT_USERNAME` | `root` | 超级管理员用户名，**只在首次初始化时生效** |
| `MONGO_INITDB_ROOT_PASSWORD` | `123456` | 超级管理员密码，**只在首次初始化时生效** |

改完执行：

```bash
cd mongo && docker compose up -d --force-recreate
```

## 客户端连接

| 场景 | 连接串 / 配置 |
|------|---------------|
| 管理员（mongosh、Compass、Navicat） | `mongodb://root:123456@192.168.110.141:27017/?authSource=admin` |
| 应用账号（只读写 `hi` 库） | `mongodb://test:123456@192.168.110.141:27017/hi?authSource=hi` |
| Spring Boot | `spring.data.mongodb.uri=mongodb://test:123456@192.168.110.141:27017/hi?authSource=hi` |
| Python（pymongo） | `MongoClient("mongodb://root:123456@192.168.110.141:27017/?authSource=admin")` |
| Node.js（mongodb 驱动） | `new MongoClient("mongodb://root:123456@192.168.110.141:27017/?authSource=admin")` |

> `authSource`（认证库）别写错：`root` 在 `admin` 库，`test` 在 `hi` 库（`test` 用 `authSource=admin` 会报
> `Authentication failed`）。用 GUI 工具时同理，要单独填「认证数据库」这一栏。

## 常见问题

1. **`WARN: the attribute version is obsolete, it will be ignored`**

   Compose V2 起 `docker-compose.yml` 顶部的 `version: '3'` 已经废弃（会被忽略），只是警告、不影响启动。
   本仓库已经把全部 compose 文件里的这行删掉了，如果还看到就说明你的文件是旧版，删掉第一行即可。

2. **容器起来就退出，日志报读不到配置文件**

   配置文件挂载点是 `/etc/mongo`，所以 `command` 必须写**容器内的绝对路径**：

   ```yaml
   command: --config /etc/mongo/mongod.conf    # 正确
   # command: --config ./config/mongod.conf    # 错误！
   ```

   官方镜像没有设置 `WORKDIR`（默认是 `/`），`./config/mongod.conf` 会被解释成 `/config/mongod.conf`，
   而容器里 `/config` 根本不存在，`mongod` 会报 `Error parsing YAML config file: unable to open file`
   然后退出（`docker compose ps` 里看不到 running）。另外镜像会把自带的 `/etc/mongod.conf` 重命名成
   `/etc/mongod.conf.orig`，所以「不挂配置直接跑」是没问题的，但**挂了 `--config` 就必须指对路径**。

3. **初始化脚本报 `mongo: command not found`**

   MongoDB **6.0 起镜像里已经删掉了老的 `mongo` shell**，只剩下 `mongosh`。老的初始化脚本里那种
   `mongo admin -u root -p 123456 --eval "..."` 写法在 6.0+ 会直接失败（并且会让 initdb 中断、容器退出）。
   `script/init.sh` 已经改成 `mongosh "mongodb://user:pass@127.0.0.1:27017/admin" --eval "..."` 的写法。

4. **日志在哪？为什么 `docker compose logs` 里没有慢查询/连接日志**

   `config/mongod.conf` 里配了 `systemLog.destination: file` + `path: /var/log/mongodb/mongod.log`，
   mongod 自己的日志全部写进文件 → 宿主机 `/data/mongodb/data/log/mongod.log`：

   ```bash
   tail -f /data/mongodb/data/log/mongod.log
   ```

   `docker compose logs` 里只有镜像入口脚本（entrypoint）那几行输出，属于正常现象。
   想让日志也进 `docker logs`，把配置文件里的 `systemLog` 段改成 `destination: stdout` 即可。

5. **改了 `.env` 里的账号密码，为什么连不上/没生效**

   `MONGO_INITDB_ROOT_*` 只在**数据目录为空**的首次初始化时用来建账号；数据目录里已经有数据时，
   入口脚本不会碰账号（也永远不该自动改密码）。真正改密码要用 mongosh：

   ```bash
   # 改 root 密码
   docker exec -it mongo mongosh -u root -p 123456 --authenticationDatabase admin \
     --eval 'db.changeUserPassword("root", "新密码")'

   # 新增一个应用账号
   docker exec -it mongo mongosh -u root -p 123456 --authenticationDatabase admin --eval '
     db.getSiblingDB("hi").createUser({
       user: "app", pwd: "app123", roles: [{ role: "readWrite", db: "hi" }]
     })
   '
   ```

   改完记得同步更新 `.env`（保证下次重建/新环境一致），但这只是记录作用。

6. **`script/init.sh` 什么时候执行？只执行一次吗**

   只在「数据目录为空」的首次启动执行一次（入口脚本判断 `/data/db` 里有没有数据）。之后 `restart`、
   `up -d`、改脚本都不会再跑。想在已有数据上重跑初始化逻辑，只能清空数据目录（常见问题 11，注意先备份），
   或者手动把脚本内容贴进 mongosh 执行一遍。

7. **`rs.status()` 报 `no replset config has been received` / 用事务报 `Transaction numbers are only allowed on a replica set member or mongos`**

   默认配置是**单机模式**（`replication` 段是注释掉的），本来就没有副本集，所以 `rs` 相关命令不可用是正常的。
   要用多文档事务（Spring `@Transactional`、`session.startTransaction()`）就按上面「单节点副本集」把副本集开起来
   （注意必须同时配 `security.keyFile`，见常见问题 16）。如果连接串里带了 `replicaSet=rs0` 而实际没开副本集，
   驱动会一直找不到 primary，报 `No primary detected for set rs0` / 超时。

8. **数据目录权限 / 容器一直重启并报 Permission denied**

   镜像里的 `mongodb` 用户是 **uid 999 / gid 999**。如果 `/data/mongodb/data/db`、`/data/mongodb/data/log`
   是 root 建的（比如你用 `sudo mkdir -p` 先建了目录），容器（以 999 身份跑）写不进去：

   ```bash
   sudo chown -R 999:999 /data/mongodb
   docker compose restart mongo
   ```

   反过来，如果你把 `user: "0:0"` 加进 compose 让容器用 root 跑，也能绕过，但那样生成的文件属主是 root，
   下次换回 999 又会有权限问题，推荐直接用 `chown`。

9. **想换大版本（8.0 / 8.3 / 7.0）行不行**

   两个硬约束：

   - **数据目录不能降级**：用 8.x 跑过的目录拿去给 7.0 启动会报 `featureCompatibilityVersion` /
     `Upgrade of the FCV` 之类的错误直接退出；
   - 升级（7.0 → 8.0 → 8.3）官方要求逐个大版本走，跳版本不保证。

   本地开发最省事：改 `.env` 的 `MONGO_VERSION`，备份→清空数据目录→重启，再用 `mongorestore` 导回来：

   ```bash
   # 备份（在老版本还跑着的时候做）
   docker exec mongo sh -c 'mongodump --uri="mongodb://root:123456@127.0.0.1:27017/?authSource=admin" --archive=/tmp/all.archive --gzip'
   docker cp mongo:/tmp/all.archive /data/mongodb/all.archive

   # 换版本 + 清数据目录（确认备份成功后再做！）
   docker compose down
   sudo rm -rf /data/mongodb/data/db/*
   # 改 MONGO_VERSION 后重新起来，再恢复
   docker compose up -d
   docker cp /data/mongodb/all.archive mongo:/tmp/all.archive
   docker exec mongo sh -c 'mongorestore --uri="mongodb://root:123456@127.0.0.1:27017/?authSource=admin" --archive=/tmp/all.archive --gzip --drop'
   ```

10. **内存占用 / `wiredTiger.cacheSizeGB` / `oplogSizeMB` 怎么理解**

    `config/mongod.conf` 里写死了 `cacheSizeGB: 1`：WiredTiger 缓存上限 1GB（默认算法是「内存的一半减 1GB」，
    开发机不用给太大，但别小于 256MB）。如果容器频繁 OOM 或大量写被刷盘卡住，把它调大一点。

    `oplogSizeMB: 51200`（默认注释掉了，只在开副本集时生效）是 oplog 体积**上限**（50GB）。
    WiredTiger 不会一上来就占满，是按需增长的，但单节点小内存机器长期跑着写入多的话，这块会慢慢把磁盘吃掉；
    不需要这么大就改成 `1024` 之类。注意：改 `cacheSizeGB` 重启容器即可；`oplogSizeMB` 在副本集已经
    `rs.initiate()` 过之后改文件不生效，要用 `replSetResizeOplog` 命令（5.0+）调整。

11. **怎么彻底重置（清空数据重新初始化）**

    ```bash
    cd mongo
    docker compose down
    sudo rm -rf /data/mongodb/data/db/* /data/mongodb/data/log/*
    docker compose up -d          # 数据目录空了 → 会重新走初始化 + 再建一次账号
    ```

    清空后 `.env` 里的 `MONGO_INITDB_ROOT_*` 会重新生效（等于换了新密码）。

12. **备份 / 恢复（不用写脚本，容器里有 `mongodump`/`mongorestore`）**

    ```bash
    # 备份单个库到宿主机
    docker exec mongo sh -c 'mongodump --uri="mongodb://root:123456@127.0.0.1:27017/?authSource=admin" --db=hi --archive=/tmp/hi.archive --gzip'
    docker cp mongo:/tmp/hi.archive /data/mongodb/hi.archive

    # 恢复（--drop 表示先删同名集合）
    docker cp /data/mongodb/hi.archive mongo:/tmp/hi.archive
    docker exec mongo sh -c 'mongorestore --uri="mongodb://root:123456@127.0.0.1:27017/?authSource=admin" --archive=/tmp/hi.archive --gzip --drop'
    ```

    也可以直接在宿主机用 `mongodump --host 192.168.110.141 --port 27017 -u root -p 123456 --authenticationDatabase admin`。

13. **Windows 上删数据目录 / 报 `manifest unknown`**

    - Windows（Docker Desktop）下宿主机路径是 `\\wsl$\docker-desktop-data\...` 或 Docker Desktop 的
      Linux 虚拟机；直接删 `E:\data\...` 里的目录常常没权限或删不干净，用一次性容器删更稳：

      ```bash
      docker run --rm -v /data/mongodb:/data alpine sh -c 'rm -rf /data/data/db/* /data/data/log/*'
      ```

    - `manifest unknown` / `no matching manifest for linux/amd64`：说明 `.env` 里的 `MONGO_VERSION`
      写了个不存在的 tag（比如 `8.0.32-alpine` 这种）。去 Docker Hub 的 `mongo` 标签页挑一个真实存在的
      tag（`8.0`、`8.0.32`、`8.0-noble`、`7.0` 等），注意 alpine 变体的 tag 形如 `8.0-alpine` 但并非每个
      版本都有，ARM/AMD64 也要对应。

14. **启动就退出，日志报 `MongoDB cannot start: Linux kernel versions 6.19 and newer has a known incompatibility with this version of MongoDB`**

    这是 MongoDB 的自我保护，不是本目录的配置写错了。Linux **6.19 ~ 7.0.13** 改了 `rseq` 的行为，和 MongoDB
    内置 TCMalloc 的 per-CPU 缓存冲突（会算错缓存，甚至写坏数据），所以 8.0.21+ / 8.3.0+ 的内核检查会
    **直接拒绝启动**（日志 `severity: F`、`id: 12257600`）。上游记录：SERVER-121912、SERVER-125742。

    先确认自己的内核：

    ```bash
    uname -r            # 6.19.x / 7.0.13 及以下（含 7.0.0-28-generic 这种发行版号）落在问题区间；
                        # 5.15 / 6.18 / 7.0.14+ / 7.1.x 都不受影响
    ```

    官方镜像里默认设了 `GLIBC_TUNABLES=glibc.pthread.rseq=0`（让 TCMalloc 自己用 rseq，性能略高），
    正好会踩中这个检查。所以本目录在 compose 里把它覆盖成 `glibc.pthread.rseq=1`
    （由 `.env` 的 `MONGO_GLIBC_TUNABLES` 控制）：这样在问题内核上 glibc 自己接管 rseq、TCMalloc 不再用
    per-CPU 缓存，mongod 就能正常启动。

    实测结果（拿官方 8.0.32 / 8.3.11 的 `mongod` 二进制伪造内核版本号跑出来的，两个版本行为一致）：

    | 内核版本 | 镜像默认 `rseq=0` | 本目录默认 `rseq=1` |
    |----------|:----------------:|:------------------:|
    | < 6.19（5.15 / 6.18 …） | ✅ 正常 | ✅ 正常 |
    | 6.19 ~ 7.0.13（含 `7.0.0-28-generic`） | ❌ 报这个错退出 | ✅ 正常 |
    | ≥ 7.0.14 / 7.1.x | ✅ 正常 | ✅ 正常 |

    想确认容器里实际生效的值：

    ```bash
    docker exec mongo env | grep GLIBC_TUNABLES     # 应该是 glibc.pthread.rseq=1
    ```

    几种可选做法：

    | 做法 | 说明 |
    |------|------|
    | `.env` 里 `MONGO_GLIBC_TUNABLES=glibc.pthread.rseq=1`（默认） | 各内核都能起；代价是 TCMalloc 的 per-CPU 缓存用不上，本地开发基本无感 |
    | `.env` 里 `MONGO_GLIBC_TUNABLES=glibc.pthread.rseq=0` | 只在内核 < 6.19 或 ≥ 7.0.14 时这么设，性能最接近镜像默认 |
    | 换 `MONGO_VERSION=7.0` | 7.0 这条线没有这个内核检查，**任何内核都能跑**（代价是版本旧一代；换版本的数据目录问题见常见问题 9） |
    | 升内核到 ≥ 7.0.14（且发行版已带 rseq 修复） | 最干净，之后 `rseq` 开不开都行 |
    | 加 `MONGO_TCMALLOC_PER_CPU_CACHE_SIZE_BYTES=0` | 另一条绕过路径（直接关掉 TCMalloc 的 per-CPU 缓存），实测一样能起来 |

    两个注意点：

    - 别把 `GLIBC_TUNABLES` 设成空字符串去「取消覆盖」（compose 里空值就真是空串，glibc 会当成未设置），
      要改就明确写 `glibc.pthread.rseq=1` 或 `glibc.pthread.rseq=0`；
    - 如果日志里不是这条报错，而是「启动后跑 60 秒左右崩」，那是 8.0.0 ~ 8.0.20 区间更老的坑（**可能损坏数据**），
      直接换成 `.env` 里的 8.0 最新补丁（当前 8.0.32）即可。

15. **启动报 `Unrecognized option: storage.journal.enabled`（或其它 `Unrecognized option`）**

    配置里留了 MongoDB 老版本的选项。`storage.journal.enabled` 是 4.0 之前用来关 journal 的开关，
    WiredTiger 从 4.0 起就不允许关 journal，这个选项在 **6.1 / 7.0 起被移除**；新版 `mongod` 看到它
    **直接报错退出**（不是告警，容器会起来就挂）：

    ```text
    Unrecognized option: storage.journal.enabled
    try 'mongod --help' for more information
    ```

    本目录 `config/mongod.conf` 里原来有这两行，现在已经删掉：

    ```yaml
    storage:
      dbPath: /data/db
      # journal:
      #   enabled: true      # ← 6.1+ 已移除，写了就启动失败
    ```

    journaling 一直是开着的，不需要（也没法）配置。改完重启容器就会重新读配置：

    ```bash
    cd mongo && docker compose restart mongo
    ```

    现在这份配置已用 **7.0.43 / 8.0.32 / 8.3.11** 三个版本的 `mongod` 实测过：都能正常启动，
    配置里的选项没有再出现未识别/弃用告警。（8.0.32 的日志里会有几条 `Use of deprecated server parameter name`，
    比如 `sslMode`、`wiredTigerConcurrentReadTransactions` —— 那是 MongoDB 自己内部调 `setParameter` 产生的，
    跟本目录的配置无关，忽略即可；7.0 / 8.3 没有这几条。）

    其它「老配置里常见、但现在已移除」的选项（8.0 实测报同一个错）：`net.http.enabled`（HTTP 接口 5.1 移除）、
    `storage.mmapv1.*`（4.2 起没有 mmapv1 引擎）、`storage.indexBuildRetry`（6.0 移除）。
    排查套路：报错信息会直接点名选项，把配置里那一行/那一段删掉或按新版文档改名即可。

16. **启动报 `BadValue: security.keyFile is required when authorization is enabled with replica sets`**

    ```text
    BadValue: security.keyFile is required when authorization is enabled with replica sets
    try 'mongod --help' for more information
    ```

    三个条件同时成立就会被拒（本目录默认配置已避开，所以默认不会报）：

    1. `.env` 里设了 `MONGO_INITDB_ROOT_USERNAME/PASSWORD` → 镜像入口脚本会给 mongod 追加 `--auth`；
    2. `config/mongod.conf` 里声明了 `replication.replSetName`（老版本仓库里这个默认是开着的）；
    3. 没有配内部认证 `security.keyFile`。

    MongoDB 的规则是：**副本集成员之间必须用 keyFile（或 x509）做内部认证**，所以「鉴权 + 副本集 + 无 keyFile」
    直接判为非法配置。三个版本（7.0.43 / 8.0.32 / 8.3.11）实测是同一个报错。
    另外注意这个报错发生在入口脚本初始化**之后**：日志前面可能已经看到建好 root 用户、跑过初始化脚本，
    最后才因这个错退出，别误判成账号问题。

    按需要三选一：

    | 你想要的形态 | 做法 |
    |--------------|------|
    | 单机 + 鉴权（本地开发默认，最省事） | 保持 `config/mongod.conf` 里 `#replication:` 的注释状态，什么都不用加 |
    | 副本集 + 鉴权（要用多文档事务） | 按上面「单节点副本集」生成 keyFile，并打开 `replication` + `security.keyFile` 两段 |
    | 副本集 + 不要鉴权 | 删掉 `.env` 里 `MONGO_INITDB_ROOT_USERNAME/PASSWORD` 两行，入口脚本就不会加 `--auth`，副本集也就不需要 keyFile（代价：数据库裸奔，只适合临时调试） |

    生效方式：只改了 `config/mongod.conf` → `docker compose restart mongo`；改了 `.env` 或 compose 文件 →
    `docker compose up -d --force-recreate`。

    keyFile 自身的两个坑（都实测过）：**权限必须 400/600**，否则报
    `InvalidPath: permissions on /... are too open`；**内容 6~1024 字节**，太大报
    `Security key size is out range ... maximumLength: 1024`（`head -c 700 /dev/urandom | base64` 约 950 字节，安全）。

> 最后提醒：这是本地开发用的单机形态（单容器、默认弱密码、数据目录直接挂宿主机）。
> 生产要用副本集 / 分片 + 独立磁盘 + 权限最小化，别照搬这里。
