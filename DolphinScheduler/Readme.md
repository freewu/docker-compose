## 说明
```
# 架构（单机版 standalone：master + worker + api + alert 全在同一个容器里）

    dolphinscheduler-postgres      元数据库（PostgreSQL 16，DolphinScheduler 专用）
    dolphinscheduler-schema-init   建表容器，执行完退出（正常现象）
    dolphinscheduler-admin-init    改管理员密码容器，执行完退出（正常现象）
    dolphinscheduler               本体，Web UI + 调度引擎

# 默认帐号密码（从 .env 读取，可外部修改）

    admin / 123456

# 使用到的端口号（宿主机映射 1:1）

    | 端口  | 所属           | 用途                              | 访问方式                                        |
    |-------|----------------|-----------------------------------|-------------------------------------------------|
    | 12345 | ds-standalone  | Web UI + REST API                 | http://localhost:12345/dolphinscheduler/ui      |
    | 25333 | ds-standalone  | Python 网关（PyDolphinScheduler）  | pydolphinscheduler 连接宿主机 25333 端口         |
    | 5433  | ds-postgres    | 元数据库（容器内是 5432）           | psql -h127.0.0.1 -p5433 -Udolphinscheduler -d dolphinscheduler |

# 仅在容器内使用、没有映射到宿主机的端口（需要的话在 docker-compose.yml 的 ports 里自行加）

    | 端口  | 组件                    | 说明                     |
    |-------|-------------------------|--------------------------|
    | 5678  | master RPC              |                          |
    | 1234  | worker RPC              |                          |
    | 50052 | alert RPC               |                          |
    | 2181  | 内嵌 ZooKeeper          | 注册中心，standalone 自带  |
    | 5432  | PostgreSQL              | 元数据库容器内端口         |

# 数据目录（宿主机绝对路径，删掉即相当于重建集群）

    /data/dolphinscheduler/postgresql   元数据（用户、租户、工作流定义与实例、数据源等）
    /data/dolphinscheduler/logs         各组件日志
    /data/dolphinscheduler/worker       任务运行临时目录
    /data/dolphinscheduler/resource     本地资源中心的文件
    /data/dolphinscheduler/soft         任务共享目录
```

## 账号密码外部配置（.env）
```
同目录下 .env 文件：

    DS_VERSION=3.4.3                  # 镜像版本（standalone 与 tools 必须一致）
    DS_DB_NAME=dolphinscheduler       # 元数据库名
    DS_DB_USER=dolphinscheduler       # 元数据库账号
    DS_DB_PASSWORD=123456             # 元数据库密码
    DS_ADMIN_USER=admin               # 内置管理员账号
    DS_ADMIN_PASSWORD=123456          # 内置管理员密码（库里存 MD5，密码没有字符限制）

# 启动（第一次启动要拉镜像 + 建表 + 起 JVM，大概 1~2 分钟）

    docker compose up -d

# 看初始化结果（两个 init 容器执行完退出是正常的）

    docker compose logs ds-schema-init
    docker compose logs ds-admin-init

# 改管理员密码：改 .env 后重跑改密码容器

    vi .env
    docker compose up -d --force-recreate ds-admin-init
    docker compose logs ds-admin-init

# 注意：如果你在 UI 里改过密码，就不要再执行 ds-admin-init（它会把密码改回 .env 里的值）。
```

## 使用与验证
```
# 1. 打开 Web UI（首次进入可能要等 1 分钟左右，JVM 启动较慢）

    http://localhost:12345/dolphinscheduler/ui
    账号：admin
    密码：.env 中的 DS_ADMIN_PASSWORD（默认 123456）

# 2. 接口健康检查（返回 UP 即正常）

    curl http://localhost:12345/dolphinscheduler/actuator/health

# 3. 看容器状态（dolphinscheduler 应为 healthy，两个 init 容器为 Exited (0)）

    docker compose ps

# 4. 直接连元数据库看看（可选）

    psql -h127.0.0.1 -p5433 -Udolphinscheduler -d dolphinscheduler
    # 或
    docker exec -it dolphinscheduler-postgres psql -Udolphinscheduler -d dolphinscheduler

    \dt                       -- 表清单（t_ds_user、t_ds_process_definition、t_ds_task_definition ...）
    SELECT id, user_name, state FROM t_ds_user;

# 5. Python 网关（装了 PyDolphinScheduler 才用得上，连宿主机的 25333）

    pip install apache-dolphinscheduler
    # 代码里把 java_gateway 的地址指向 宿主机IP:25333 即可
```

## 常见问题
```
# 1. 拉不到镜像（Docker Hub 超时）

    给 Docker 配置国内镜像加速，或在 .env 里把 DS_VERSION 换成其它可用版本后重试。

# 2. ds-schema-init 执行失败

    docker compose logs ds-schema-init
    常见原因是元数据库还没起来（会自动重试）或挂载目录没有写权限。
    想彻底重建元数据：docker compose down && rm -rf /data/dolphinscheduler/postgresql/pgdata

# 3. ds-admin-init 提示"等待元数据库超时"

    说明建表没成功，先解决第 2 条；确认账号名是否被改过（.env 的 DS_ADMIN_USER）。

# 4. UI 打不开 / 一直转圈

    先看日志：docker compose logs -f dolphinscheduler，等出现 "Started StandaloneServer" 再访问；
    端口被占用就改 docker-compose.yml 里 ports 左侧的 12345（右侧容器内端口不要改）。

# 5. 忘记管理员密码

    把 .env 里的 DS_ADMIN_PASSWORD 改成想要的值，然后：
    docker compose up -d --force-recreate ds-admin-init

# 6. 时间不对（差 8 小时）

    容器时区是 TZ=Asia/Shanghai；JVM/Jackson 时区由 SPRING_JACKSON_TIME_ZONE 控制，
    这里沿用官方示例的 UTC。UI 上显示的时间跟「用户中心 → 时区」设置有关，按需调整。

# 7. 升级版本

    改 .env 里的 DS_VERSION（standalone/tools 共用一个变量），然后 docker compose up -d；
    ds-schema-init 会自动把表结构升级到新版本。

# 8. 数据会不会丢

    元数据在 /data/dolphinscheduler/postgresql（独立 PostgreSQL），容器重启/重建都不丢；
    只要不删这个目录（以及不用 H2 内存库）就不会丢。
```
