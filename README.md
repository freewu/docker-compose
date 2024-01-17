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

  服务          |   目录             |  说明
--------------- |------------------ | ---------------------------------------
Redis           | redis             | NoSql 数据库
Mysql           | mysql             | RMDBS 关系型数据库
PostgreSQL      | postgre           | RMDBS 关系型数据库
RabbitMQ        | rabbitmq          | 消息队列
MQTT            | mqtt              | 消息队列 (用于物联网)
Portainer       | postainer         | Docker 服务管理
Mosquitto       | mosquitto         | 消息队列 (用于物联网) 走MQTT协议
MongoDB         | mongo             | 文档数据库
Minio           | minio             | 分布式文件存储系统
Milvus          | milvus            | 向量数据库
Kafka           | kafka             | 消息队列
InfluxDB        | influxdb          | 时序数据库
Etcd            | etcd              | 分布式 Key-Value 存储
ElasticSearch   | elastic-search    | 全文搜索数据库
Clickhouse      | clickhouse        | OLAP 数据库




