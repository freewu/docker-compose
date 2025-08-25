## docker-compose

    使用 docker 构建开发环境脚本


## 使用方式
```
# 进入需要启动服务的目录(如: Redis )

    cd redis

# 启动 

    docker-compose up -d
    
```

## 支持服务

  服务          |   目录             |  占用端口                                   |  说明
--------------- |------------------ | -------------------------------------------------------------------------------
Redis           | redis             |  6379                                     | NoSql 数据库
Redis-Sentinel  | redis-sentinel    |  26379,26380,26381,5540,6379,6380,6381    | NoSql 数据库 Redis 哨兵模式
Mysql           | mysql             |  3306                                     | RMDBS 关系型数据库
PostgreSQL      | postgre           |  5432                                     | RMDBS 关系型数据库
RabbitMQ        | rabbitmq          |  15672,5672                               | 消息队列
MQTT            | mqtt              |  18083,1883,8084,8883,8083                | 消息队列 (用于物联网)
Portainer       | postainer         |  8001,9001                                | Docker 服务管理
Mosquitto       | mosquitto         |  1883                                     | 消息队列 (用于物联网) 走MQTT协议
MongoDB         | mongo             |  27017                                    | 文档数据库
Minio           | minio             |  9003,9004                                | 分布式文件存储系统
Milvus          | milvus            |  19530,9091                               | 向量数据库
Kafka           | kafka             |  9092                                     | 消息队列
InfluxDB        | influxdb          |  8086,8083                                | 时序数据库
Etcd            | etcd              |                                           | 分布式 Key-Value 存储
ElasticSearch   | elastic-search    |  9200,9800                                | 全文搜索数据库
Clickhouse      | clickhouse        |  8123,9000                                | OLAP 数据库
Chroma          | chroma            |                                           | 向量数据库
