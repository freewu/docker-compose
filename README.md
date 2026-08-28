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

## 支持服务

| 服务名称        | 目录名称           | 占用端口                                  | 说明                                    |
|----------------|------------------|------------------------------------------|----------------------------------------|
| Redis          | redis            | 6379                                     | NoSql 数据库                            |
| Redis-Sentinel | redis-sentinel   | 26379,26380,26381,5540,6379,6380,6381    | NoSql 数据库 Redis 哨兵模式              |
| MySQL          | mysql            | 3306                                     | RMDBS 关系型数据库                       |
| PostgreSQL     | postgre          | 5432                                     | RMDBS 关系型数据库                       |
| RabbitMQ       | rabbitmq         | 15672,5672                               | 消息队列                                |
| MQTT           | mqtt             | 18083,1883,8084,8883,8083                | 消息队列 (用于物联网)                     |
| Portainer      | postainer        | 8001,9001                                | Docker 服务管理                         |
| Mosquitto      | mosquitto        | 1883                                     | 消息队列 (用于物联网) 走MQTT协议           |
| MongoDB        | mongo            | 27017                                    | 文档数据库                               |
| Minio          | minio            | 9003,9004                                | 分布式文件存储系统                        |
| Milvus         | milvus           | 19530,9091                               | 向量数据库                               |
| Kafka          | kafka            | 9092                                     | 消息队列                                |
| InfluxDB       | influxdb         | 8086,8083                                | 时序数据库                              |
| Etcd           | etcd             | -                                        | 分布式 Key-Value 存储                   |
| ElasticSearch  | elastic-search   | 9200,9800                                | 全文搜索数据库                           |
| Clickhouse     | clickhouse       | 8123,9000                                | OLAP 数据库                             |
| Chroma         | chroma           | -                                        | 向量数据库                               |
| Memcached      | memcached        | 11211                                    | 内存缓存服务                             |
| Doris          | doris            | 8041,8042,8043                           | OLAP 数据库                             |
| MariaDB        | mariadb          | 3307                                     | 关系型数据库                             |

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
