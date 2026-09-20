# MongoDB

MongoDB 单机版（文档数据库 / NoSQL），用于本地开发调试。

| 项目 | 说明 |
|------|------|
| 镜像 | `mongo`（版本见 `.env` 的 `MONGO_VERSION`，默认 `8.0` LTS，即 8.0.32；当前 latest 是 8.3.11） |
| 容器名 | `mongo` |
| 启动方式 | `mongod --config /etc/mongo/mongod.conf`（配置文件里开了 `replSetName: rs0`，见「单节点副本集」） |
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
> 配置文件里写了副本集名 `rs0`、但**必须手动 `rs.initiate()` 才真正生效**（不开也能用，只是不能用多文档事务），见下面「单节点副本集」。

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

## 单节点副本集（rs0）

`config/mongod.conf` 里开了：

```yaml
replication:
  oplogSizeMB: 51200
  replSetName: rs0
```

只是**声明**了副本集名，`mongod` 起来后副本集仍是「未初始化」状态：

- 普通增删改查、`mongosh`、大部分驱动都能正常用；
- 但 `rs.status()` 会报 `NotYetInitialized: no replset config has been received`；
- **多文档事务**（`session.startTransaction()`，Spring 的 `@Transactional`）必须副本集，不初始化就用不了。

要用事务（或想让副本集真正就绪）就初始化一次，成员的 host **要写宿主机局域网 IP**，否则别的机器/容器连上来会拿到一个连不通的地址：

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

如果不想要副本集（单机够用、避开这些麻烦）：把 `config/mongod.conf` 里的 `replication:` 两行删掉，
清空数据目录重启即可（常见问题 11）。注意：**删掉副本集配置后原来的数据只能用在新目录里**，
换回来同理，别拿同一份数据目录来回切。

## `.env` 配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MONGO_VERSION` | `8.0` | 镜像 tag，固定大版本（`8.0` = LTS / `8.3` = 最新 / `7.0` = 上一代 LTS） |
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

7. **`rs.status()` 报 `no replset config has been received`**

   这是「声明了副本集名但没初始化」的正常状态，不影响普通读写；要用事务就按上面「单节点副本集」跑一次
   `rs.initiate()`。如果客户端连接串带了 `replicaSet=rs0` 而没初始化过，驱动会一直找不到 primary，
   报 `No primary detected for set rs0` / 超时。

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

    `oplogSizeMB: 51200` 是 oplog 体积**上限**（50GB）。WiredTiger 不会一上来就占满，是按需增长的，
    但单节点小内存机器长期跑着写入多的话，这块会慢慢把磁盘吃掉；不需要这么大就改成 `1024` 之类。
    注意：改这两个值都需要重启容器；改 `oplogSizeMB` 后如果副本集已初始化，还需要 `rs.reconfig` 才会生效。

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

> 最后提醒：这是本地开发用的单机形态（单容器、默认弱密码、数据目录直接挂宿主机）。
> 生产要用副本集 / 分片 + 独立磁盘 + 权限最小化，别照搬这里。
