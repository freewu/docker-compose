## docker-compose

    使用 docker 构建开发环境脚本

## 前置 docker-compose 安装
### 安装 docker-compose v1 (ubuntu)
```bash
# 安装 docker-compose v1
sudo apt-get update
sudo apt-get install -y docker-compose
```

### 安装 compose v2 插件（推荐，`docker compose` 空格命令）
```bash
# 创建系统插件目录
sudo mkdir -p /usr/local/lib/docker/cli-plugins

# 下载 compose v2 二进制（x86_64）
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose

# 赋予执行权限
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

```

### 独立二进制 `docker-compose`（带横杠，v2，不用 python，避开 distutils 报错）
```bash
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

## 使用方式
```
# 进入需要启动服务的目录(如: Redis )

    cd redis

# 启动 

    # 旧版本启动方式
    #docker-compose up -d
    # 新版本启动方式
    docker compose up -d
    
```

> 注意：`redis-sentinel`、`redis-cluster`、`kafka`、`rocketmq` 需要 `HOST_IP`（宿主机局域网 IP），不能是 `127.0.0.1`。
> `redis-cluster` 已提供脚本自动探测并写入 `.env`：`cd redis-cluster && ./set-host-ip.sh`
> `kafka`、`rocketmq` 的 IP 写在各自的 `.env`（`kafka/.env`、`rocketmq/.env`），探测：`redis-cluster/set-host-ip.sh --print`
> `redis-sentinel` 手动导出即可：`export HOST_IP=192.168.0.200 && docker compose up -d`（换成你自己的局域网 IP）
>
> 账号密码支持外部配置（各服务目录下 `.env`，改完重建容器生效）：
> `clickhouse/.env`（`CLICKHOUSE_USER` / `CLICKHOUSE_PASSWORD`）、`doris/.env`（`DORIS_ROOT_PASSWORD`）、`tidb/.env`（`TIDB_ROOT_PASSWORD`）、`DolphinScheduler/.env`（`DS_DB_PASSWORD` / `DS_ADMIN_PASSWORD`）、`nacos/.env`（`NACOS_ADMIN_PASSWORD` 及鉴权密钥）、`ActiveMQ/.env`（`ACTIVEMQ_ADMIN_PASSWORD`）。

## 支持服务

| 服务名称        | 目录名称           | 占用端口                                  | 说明                                    |
|----------------|------------------|------------------------------------------|----------------------------------------|
| Redis          | redis            | 6379                                     | NoSql 数据库（密码 123456）              |
| Redis-Sentinel | redis-sentinel   | 26379,26380,26381,5540,6379,6380,6381    | NoSql 数据库 Redis 哨兵模式（密码 123456）|
| Redis-Cluster  | redis-cluster    | 7001,7002,7003,7004,7005,7006,17001,17002,17003,17004,17005,17006 | NoSql 数据库 Redis 集群模式 3主3从（密码 123456）|
| MySQL          | mysql            | 3306                                     | RMDBS 关系型数据库                       |
| PostgreSQL     | postgre          | 5432                                     | RMDBS 关系型数据库                       |
| RabbitMQ       | rabbitmq         | 15672,5672                               | 消息队列                                |
| MQTT           | mqtt             | 18083,1883,8084,8883,8083                | 消息队列 (用于物联网)                     |
| Portainer      | postainer        | 8001,9001                                | Docker 服务管理                         |
| Mosquitto      | mosquitto        | 1883                                     | 消息队列 (用于物联网) 走MQTT协议           |
| MongoDB        | mongo            | 27017                                    | 文档数据库                               |
| Minio          | minio            | 9003,9004                                | 分布式文件存储系统                        |
| Milvus         | milvus           | 19530,9091                               | 向量数据库                               |
| Kafka          | kafka            | 9092,2182                                | 消息队列（`KAFKA_ADVERTISED_LISTENERS` 需同目录 .env 的 `HOST_IP`）|
| InfluxDB       | influxdb         | 8086,8083                                | 时序数据库                              |
| Etcd           | etcd             | -                                        | 分布式 Key-Value 存储                   |
| ElasticSearch  | elastic-search   | 9200,9800                                | 全文搜索数据库                           |
| Clickhouse     | clickhouse       | 8123,9000                                | OLAP 数据库（账号密码由 .env 提供，默认 bluefrog / 12345678）|
| Chroma         | chroma           | -                                        | 向量数据库                               |
| Memcached      | memcached        | 11211                                    | 内存缓存服务                             |
| Doris          | doris            | 8031,8032,8033,9031,9032,9033,8041,8042,8043 | OLAP 数据库（root 密码由 .env 提供，默认 123456）|
| MariaDB        | mariadb          | 3307                                     | 关系型数据库                             |
| TiDB           | tidb             | 4000,10080,2379,2380,20160,20180         | NewSQL 数据库 MySQL 协议（root 密码由 .env 提供，默认 123456）|
| DolphinScheduler | DolphinScheduler | 12345,25333,5433                       | 分布式工作流任务调度（admin 密码由 .env 提供，默认 123456）|
| Nacos          | nacos            | 8080,8848,9848                           | 服务注册与配置中心（控制台端口 8080，账号 nacos，密码由 .env 提供，默认 123456）|
| Consul         | consul           | 8500,8600                                | 服务注册与配置中心（单节点 server，Web UI 8500 + DNS 8600，默认不开 ACL）|
| RustFS         | rustfs           | 9020,9021                                | 对象存储（S3 兼容，控制台 9021 路径前缀 /rustfs/console/，账号密码由 .env 提供，默认 rustfs/123456）|
| RocketMQ       | rocketmq         | 9876,10911,10909,10912,8180              | 消息队列（NameServer 9876 + Broker 10911/10909/10912 + 控制台 8180；`brokerIP1` 取同目录 .env 的 `HOST_IP`）|
| ActiveMQ       | ActiveMQ         | 61616,8161,61613,61614,5673,11883        | 消息队列（Classic 单机，OpenWire 61616 + 控制台 8161；AMQP 宿主机 5673、MQTT 宿主机 11883，避开 rabbitmq 5672 / mosquitto 1883）|

## docker hub 镜像
```bash
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.xuanyuan.me",
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io"
  ]
}
EOF

# 重载配置
systemctl daemon-reload
# 重启docker
systemctl restart docker
```
