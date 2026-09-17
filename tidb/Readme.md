## 说明
```
# 架构（单机版，1 PD + 1 TiKV + 1 TiDB Server + 1 初始化容器）

    tidb-pd    PD（集群元信息，2379/2380）
    tidb-tikv  TiKV（数据存储，20160/20180）
    tidb       TiDB Server（MySQL 协议，4000/10080）
    tidb-init  用 .env 中的密码设置 root 账号，执行完自动退出（属正常现象）

# 默认帐号密码（从 .env 读取，可外部修改）

    root / 123456

# 使用到的端口号（宿主机映射 1:1）

    | 端口  | 组件 | 用途                | 访问示例                            |
    |-------|------|---------------------|-------------------------------------|
    | 4000  | TiDB | MySQL 协议端口       | mysql -h127.0.0.1 -P4000 -uroot -p  |
    | 10080 | TiDB | 状态/监控端口        | curl http://127.0.0.1:10080/status |
    | 2379  | PD   | 客户端端口           | curl http://127.0.0.1:2379/pd/api/v1/stores |
    | 2380  | PD   | 集群内部通信端口      | -                                   |
    | 20160 | TiKV | 服务端口             | -                                   |
    | 20180 | TiKV | 状态端口             | curl http://127.0.0.1:20180/status |

# 数据目录（宿主机绝对路径，删除即相当于重建集群）

    /data/tidb/pd      PD 元信息
    /data/tidb/tikv    TiKV 业务数据
    /data/tidb/tidb    TiDB 日志
```

## 账号密码外部配置（.env）
```
同目录下 .env 文件：

    TIDB_ROOT_USER=root          # TiDB 内置管理员账号就是 root，一般不用改
    TIDB_ROOT_PASSWORD=123456    # root 登录密码（TiDB 默认空密码）

# 启动（TiDB 组件启动顺序：PD -> TiKV -> TiDB，预计 30~60 秒）

    docker compose up -d

# 查看设置密码的结果（tidb-init 执行完退出属正常现象）

    docker compose logs -f tidb-init

# 修改密码：编辑 .env 后重建 tidb-init 即可

    vi .env
    docker compose up -d --force-recreate tidb-init
    docker compose logs -f tidb-init

# 注意：账号信息存在 PD/TiKV 数据里，不随 .env 自动变化。
#       如果手动改过 root 密码，请把 .env 中的 TIDB_ROOT_PASSWORD 改成同一个值，
#       否则 tidb-init 会提示"已有其它密码"（不会覆盖，避免误改）。
```

## 连接与验证
```
# 使用 mysql 客户端连接（宿主机上，TiDB 兼容 MySQL 协议）

    mysql -h127.0.0.1 -P4000 -uroot -p123456

# 常用校验

    SELECT VERSION();                                -- TiDB 版本
    SELECT * FROM INFORMATION_SCHEMA.CLUSTER_INFO;   -- 集群各组件状态
    SHOW DATABASES;
    CREATE DATABASE demo; USE demo;
    CREATE TABLE t (id INT PRIMARY KEY, name VARCHAR(20));
    INSERT INTO t VALUES (1, 'hello'); SELECT * FROM t;

# 各组件状态接口

    curl http://127.0.0.1:10080/status               # TiDB
    curl http://127.0.0.1:2379/pd/api/v1/stores     # PD
    curl http://127.0.0.1:20180/status              # TiKV

# 容器内连接（去掉了宿主机端口映射）

    docker exec -it tidb mysql -h127.0.0.1 -P4000 -uroot -p123456
```

## 常见问题
```
# 1. 拉镜像报 manifest unknown / not found

    说明该版本镜像不存在，把 docker-compose.yml 里三个组件的 image 换成同一版本号即可
    （pd / tikv / tidb 必须一致），例如：

        pingcap/pd:v8.5.5   pingcap/tikv:v8.5.5   pingcap/tidb:v8.5.5

# 2. tidb-init 提示"已有其它密码"

    root 现有密码与 .env 中的 TIDB_ROOT_PASSWORD 不一致，把 .env 改成现有密码即可；
    确实忘了密码就重建集群：

        docker compose down
        rm -rf /data/tidb/*
        docker compose up -d

# 3. tidb-init 提示"等待 TiDB 超时"

    组件没起来，按顺序看日志：docker compose logs -f tidb-pd、tidb-tikv、tidb。
    常见原因是 2379/2380/20160/20180 端口被占用，或挂载目录没有写权限。

# 4. 端口冲突

    上面 6 个端口任一被占用都会启动失败，改 ports 左侧的数字即可
    （右侧容器内端口与集群通信相关，不要改）。
```
