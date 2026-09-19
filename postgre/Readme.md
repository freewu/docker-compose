# PostgreSQL

PostgreSQL 单机版（关系型数据库），用于本地开发/调试。

| 项目 | 说明 |
|------|------|
| 镜像 | `postgres`，版本见 `.env` 的 `POSTGRES_VERSION`（默认 `18.6`，**固定大版本**） |
| 容器名 | `postgres` |
| 端口 | **5432**（宿主机）→ 容器内 5432 |
| 账号密码 | 见 `.env`（`POSTGRES_USER` / `POSTGRES_PASSWORD`，默认 `root` / `root`；初始库 `POSTGRES_DB`，默认 `root`） |
| 数据目录 | `/data/postgresql` → 容器内 `/var/lib/postgresql`；**实际数据在 `/data/postgresql/18/docker`**（18 = PG 大版本号） |
| 目录结构 | `.env` + `docker-compose.yml` + `Readme.md`，不需要额外配置文件（用镜像默认 `postgresql.conf`，需要改就把配置放到 `conf.d` 或挂 `postgresql.conf`） |

> ⚠️ **18+ 的挂载点和老版本不一样**（这也是最容易踩的坑）：
> 官方 18 起把 `PGDATA` 改成了 `/var/lib/postgresql/<大版本>/docker`，`VOLUME` 从 `/var/lib/postgresql/data`
> 挪到了 `/var/lib/postgresql`，所以 compose 里必须挂 **`/data/postgresql:/var/lib/postgresql`**。
> 挂成老写法 `/var/lib/postgresql/data` 会直接启动失败并报
> `Error: in 18+, these Docker images are configured to store database data in a format ...`（见常见问题 1）。

## 使用到的端口

| 端口 | 容器内 | 用途 | 说明 |
|------|:---:|------|------|
| **5432** | 5432 | PostgreSQL 协议 | `postgresql://root:root@192.168.110.141:5432/root`；本仓库只有本目录使用 5432 |
| 5433 | 5432 | —— | 被 `DolphinScheduler` 的元数据库实例占用（那是**另一个** PG 容器，`dolphinscheduler-postgres`），别连错 |

端口占用自查：

```bash
ss -lntp | grep 5432
```

容器内没有其它对外端口（PG 只有一个监听端口；`/var/run/postgresql/.s.PGSQL.5432` 是容器内的 Unix socket）。

## 启动

```bash
cd postgre
docker compose up -d
docker compose ps                         # 等 STATUS 出现 (healthy)，首次初始化约 5~15 秒
docker compose logs -f postgres           # 看到 "database system is ready to accept connections" 即成功
```

## 验证

```bash
# 容器内 psql（不需要密码，走本地 socket）
docker exec -it postgres psql -U root -d root -c '\l'
docker exec -it postgres psql -U root -d root -c 'select version()'

# 数据目录到底在哪（应输出 /var/lib/postgresql/18/docker）
docker exec -it postgres psql -U root -c 'show data_directory'
docker exec -it postgres ls -l /var/lib/postgresql

# 宿主机连（需要本机装了 psql / 客户端工具）
psql -h 127.0.0.1 -p 5432 -U root -d root -c 'select 1'
```

连接串：

| 场景 | 连接串 |
|------|--------|
| JDBC（Java） | `jdbc:postgresql://192.168.110.141:5432/root`，user `root`，password `root` |
| DSN（psql / psycopg / Go） | `postgresql://root:root@192.168.110.141:5432/root` |
| Spring Boot | `spring.datasource.url=jdbc:postgresql://192.168.110.141:5432/root`、`spring.datasource.username=root`、`spring.datasource.password=root` |
| 客户端工具 | DBeaver / Navicat / pgAdmin：主机 `192.168.110.141`，端口 `5432` |

## 配置说明（.env）

改完执行 `docker compose up -d --force-recreate` 生效：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `POSTGRES_VERSION` | `18.6` | 镜像 tag。**必须固定大版本**，用 `image: postgres` 会跟着 `latest` 走（现在是 18，将来是 19） |
| `POSTGRES_USER` | `root` | 超级用户（**只在首次初始化时生效**） |
| `POSTGRES_PASSWORD` | `root` | 上面的用户密码（只在首次初始化时生效） |
| `POSTGRES_DB` | `root` | 初始库名（只在首次初始化时生效；不写时默认等于 `POSTGRES_USER`） |

改之前要清楚：`POSTGRES_*` **只在数据目录为空时**用于初始化数据库。数据已经存在后：

- 改 `POSTGRES_PASSWORD` **不会**改数据库里已有账号的密码（见常见问题 6）；
- 改 `POSTGRES_VERSION` 到另一个大版本，等于用新版本的 `PGDATA` 子目录（如 `19/docker`）→ **空库**，不是自动升级（见常见问题 3）。

其它常用可选变量（需要时自己加到 `environment:` 里）：

| 变量 | 作用 |
|------|------|
| `POSTGRES_INITDB_ARGS` | 首次 `initdb` 的参数，如 `--data-checksums`、`--encoding=UTF8 --locale=C.UTF-8` |
| `POSTGRES_HOST_AUTH_METHOD` | 覆盖 `pg_hba.conf` 的认证方式（默认 `scram-sha-256`；调试可临时用 `trust`，别在开放网络里用） |
| `POSTGRES_INITDB_WALDIR` | 把 WAL 放到另一个目录（性能调优用） |

初始化脚本 / 备份还原：把 `.sql`、`.sql.gz`、`.sh` 放到 `/docker-entrypoint-initdb.d` 会在**首次初始化时**自动执行。
要这个能力就加一行挂载（例如 `- /data/postgresql/source:/docker-entrypoint-initdb.d`）。

## 常见问题

1. **启动就退出，报 `in 18+, these Docker images are configured to store database data in a format ...`**

   这是官方 18+ 的**刻意的**保护性报错（`exit 1`），意思是「18 的数据布局变了，但你这里的数据/挂载还是老布局」。
   报错里最关键的一行是它列出的路径，看是哪种：

   | 报错里列的路径 | 含义 | 处理 |
   |----------------|------|------|
   | `/var/lib/postgresql/data (unused mount/volume)` | **没有旧数据**，只是你把 volume 挂在了老的 `/var/lib/postgresql/data` 上（容器里检测到那是个挂载点且里面没有 `PG_VERSION`） | 把挂载点改成 `/var/lib/postgresql` 即可（本目录已经是这么写的），重启即全新初始化 |
   | `/var/lib/postgresql` 或 `/var/lib/postgresql/data` | **确实存在旧版本的数据**（该目录下有 `PG_VERSION`） | 要么继续用老版本（见下），要么把数据迁到 18（`pg_upgrade` / 逻辑备份导入） |

   官方原话的修法：**"place a single mount at /var/lib/postgresql"** —— 即：

   ```yaml
   volumes:
     - /data/postgresql:/var/lib/postgresql      # 18+ 的写法（本目录默认）
     # - /data/postgresql:/var/lib/postgresql/data   # ≤17 的老写法，18 会直接报错
   ```

   想继续用老布局（数据能直接用、不折腾）：把 `.env` 的版本固定到 17 及以下，挂载改回老写法：

   ```
   POSTGRES_VERSION=17.11
   ```

   ```yaml
   volumes:
     - /data/postgresql:/var/lib/postgresql/data
   ```

2. **真想把 ≤17 的老数据搬到 18（不删数据）**

   大版本之间必须升级（PG 不支持跨大版本直接启动读数据）。开发环境最省事的是**逻辑备份 + 导入**：

   ```bash
   # 0) 准备一个能被容器内 postgres 用户（uid 999）写的备份目录
   sudo mkdir -p /data/pgbackup && sudo chown -R 999:999 /data/pgbackup

   # 1) 用老版本（这里以 17 为例）把老数据跑起来，做逻辑备份
   #    假设老数据就在 /data/postgresql 根目录下（该目录里有 PG_VERSION、base/ 等）
   docker run --rm -v /data/postgresql:/olddata -v /data/pgbackup:/backup postgres:17.11 \
     sh -c 'chown -R postgres:postgres /olddata && su postgres -c "pg_ctl -D /olddata -o \"-p 5439\" -w start" \
            && su postgres -c "pg_dumpall -p 5439 -f /backup/all.sql" \
            && su postgres -c "pg_ctl -D /olddata -o \"-p 5439\" -m fast stop"'

   # 2) 备份先放到安全的地方（/data/postgresql 马上要被新版本重新组织）
   sudo mv /data/postgresql /data/postgresql.old
   sudo mkdir -p /data/postgresql
   sudo mv /data/pgbackup /data/postgresql/ && sudo chown -R 999:999 /data/postgresql    # 顺手把备份放进挂载目录

   # 3) 起 18，把备份导入（角色 + 各库都在这个 dump 里）
   docker compose up -d
   docker exec -i postgres psql -U root -d postgres -f /var/lib/postgresql/pgbackup/all.sql
   ```

   确认没问题后再删 `/data/postgresql.old` 腾空间。

   数据量大、要求在线升级就用官方建议的 `pg_upgrade --link`（正好受益于 18 的「单挂载点 + 大版本子目录」设计），
   参考 <https://github.com/docker-library/postgres/issues/37>。

3. **数据在哪 / 换大版本后会怎样**

   ```bash
   docker exec -it postgres psql -U root -c 'show data_directory'   # /var/lib/postgresql/18/docker
   ls -l /data/postgresql                                            # 宿主机：18/（里面才是 docker/）
   ```

   目录名里的 `18` 是 `PG_MAJOR`，所以**升级大版本不会覆盖老数据**（会新建 `19/docker`），但新目录是**空库**，
   老数据要用 `pg_upgrade` 或逻辑导入迁过去。这也是 18+ 改布局的目的。

4. **端口 5432 连不上 / 和 DolphinScheduler 混淆**

   - 确认 `docker compose ps` 里有 `0.0.0.0:5432->5432/tcp`，宿主机也没别的服务占用 5432（`ss -lntp | grep 5432`）；
   - 本目录是 `root/root`、库 `root`；`DolphinScheduler` 的元数据库在宿主机 **5433**、账号 `dolphinscheduler`，
     两者完全独立，连不上时先看自己连的是哪个端口；
   - 容器内的应用可以直接用服务名连：`postgres:5432`（同网络时）。

5. **报 `could not resize shared memory segment` / 大查询被 OOM kill**

   - 前者是容器 `/dev/shm` 太小（默认 64MB），本目录已设 `shm_size: 256mb`，还不够就继续调大；
   - 后者是容器内存不够，给 compose 加 `mem_limit`/`deploy.resources` 或调小 `shared_buffers`、`work_mem`
     （需要挂自定义 `postgresql.conf` 或用 `command: postgres -c shared_buffers=256MB -c work_mem=8MB`）。

6. **改了 `.env` 里的密码，为什么登录密码没变**

   `POSTGRES_PASSWORD` 只在**首次初始化**时用来创建用户。已经有数据后改它没有任何效果，要改密码得进库执行 SQL：

   ```bash
   docker exec -it postgres psql -U root -c "ALTER USER root WITH PASSWORD 'newpass';"
   ```

   （容器里的旧密码仍能用是因为账号密码存在数据目录里，不在 compose 文件里。）

7. **客户端报 `password authentication failed` 或老客户端不支持 `scram-sha-256`**

   18 默认 `password_encryption = scram-sha-256`，PG 14 之前的老客户端 / 老驱动可能握手失败。两种办法：

   - 升级客户端驱动（推荐，`org.postgresql:postgresql` 用 42.7+）；
   - 临时降级认证方式（仅本地开发）：

     ```bash
     docker exec -it postgres psql -U root -c "SET password_encryption='md5'; ALTER USER root WITH PASSWORD 'root';"
     ```

     并在 `pg_hba.conf` 里把对应行的 `scram-sha-256` 改成 `md5`（`pg_hba.conf` 在数据目录里：
     `/data/postgresql/18/docker/pg_hba.conf`，改完 `docker restart postgres`）。

8. **挂载目录权限报错（`initdb: could not change permissions of directory` / `Permission denied`）**

   镜像启动时先用 root 准备数据目录再降权到 `postgres`（uid 999），正常不会出问题；宿主机目录属主异常时修一下：

   ```bash
   sudo chown -R 999:999 /data/postgresql
   docker compose up -d --force-recreate
   ```

   NFS / Windows 共享目录上挂 PG 数据目录容易出各种权限与锁问题，建议放在本地磁盘。

9. **清空/重置数据库（回到全新状态）**

   ```bash
   docker compose down
   sudo rm -rf /data/postgresql/*            # 数据全没，慎用；Windows(Docker Desktop) 见第 11 条
   docker compose up -d
   ```

   只想删一个库/表就用 SQL（`DROP DATABASE xxx;`），不用动数据目录。

10. **备份 / 恢复**

    ```bash
    # 备份单库（自定义格式，可用 pg_restore 选择性恢复）
    docker exec -it postgres pg_dump -U root -d root -Fc -f /var/lib/postgresql/backup.dump
    # 备份全部库 + 角色（纯 SQL）
    docker exec -it postgres pg_dumpall -U root -f /var/lib/postgresql/all.sql
    # 恢复
    docker exec -i postgres psql -U root -d root < backup.sql
    docker exec -i postgres pg_restore -U root -d root --clean /var/lib/postgresql/backup.dump
    ```

    文件写在 `/var/lib/postgresql/...` 就等于写在宿主机 `/data/postgresql/...`，容器删了也还在。

11. **Windows（Docker Desktop）上怎么删数据目录**

    ```bash
    docker run --rm -v /data/postgresql:/data alpine sh -c "rm -rf /data/*"
    ```

12. **报 `manifest unknown` / 镜像拉不动**

    `POSTGRES_VERSION` 写的 tag 不存在，或网络拉不动 Docker Hub。去 Docker Hub 的 `postgres` 页面挑一个存在的 tag
    （如 `18.6`、`18.6-alpine`、`17.11`），内网环境把 `image:` 换成自己的镜像仓库地址。

13. **想用 `alpine` 版本 / 中文排序**

    - 体积小可以把版本写成 `18.6-alpine`（musl libc，个别扩展/工具行为有差异，本地开发够用）；
    - 需要中文排序（`zh_CN.UTF-8` 或 `C.UTF-8`）在首次初始化时决定，事后改不了：
      `POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8`，然后删掉数据目录重新初始化。
