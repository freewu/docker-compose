# Kafka

Apache Kafka 单节点（ZooKeeper 模式），用于本地开发/调试消息队列。

| 项目 | 说明 |
|------|------|
| 镜像 | `kafka:latest`（**本地镜像**，见下面说明）、`zookeeper:latest` |
| 容器名 | `kafka`、`kafka-zookeeper` |
| 数据目录 | `/data/kafka`、`/data/zookeeper` |
| 默认 topic | `kafeidou`（2 分区、0 副本，由 `KAFKA_CREATE_TOPICS` 自动创建） |

> ⚠️ `image: kafka:latest` 指的是**本地已有的镜像**（老式 wurstmeister 风格的环境变量写法：`KAFKA_ADVERTISED_LISTENERS` / `KAFKA_ZOOKEEPER_CONNECT` / `KAFKA_CREATE_TOPICS`）。
> 如果本机没有这个镜像，`docker compose up -d` 会报 `pull access denied`，两种处理方式：
> 1. 换成官方镜像 `apache/kafka:3.9.0` 或 `bitnami/kafka:3.9`，但环境变量写法要随之调整（或按官方文档加 KRaft 配置）；
> 2. 保留原样，把本地构建/保存的 `kafka:latest` 镜像 `docker load` 进来。

## 使用到的端口

| 端口 | 协议 | 用途 |
|------|------|------|
| **9092** | TCP | Kafka broker（客户端连接端口） |
| **2182** | TCP | ZooKeeper（宿主机侧用 2182，避开其它服务常用的 2181；容器内仍是 2181） |

两个端口在本仓库其它服务中都没有使用，不会冲突。

## 必填：HOST_IP（宿主机局域网 IP）

`KAFKA_ADVERTISED_LISTENERS` 是 broker 告诉客户端「接下来连我这个地址」，**必须是宿主机局域网 IP，不能是 `127.0.0.1`**：

- 填 `127.0.0.1`：只有宿主机自己能用，容器/其它机器上的客户端会连不上；
- 填错 IP：会出现「TCP 能连上 9092，但生产/消费时报 `Connection to node 0 could not be established`」。

配置在同目录 `.env`：

```dotenv
HOST_IP=192.168.0.200
```

探测本机当前 IP（不动任何文件，只打印）：

```bash
../redis-cluster/set-host-ip.sh --print
```

改完 `.env` 后重建：

```bash
docker compose up -d --force-recreate kafka9094
```

> 本机 IP 变化（换网络、路由器重新分配）后要同步改这里，否则客户端会莫名其妙连不上。

## 启动

```bash
cd kafka
docker compose up -d
docker compose ps
docker compose logs -f kafka9094     # 看到 started (kafka.server.KafkaServer) 即成功
```

## 验证

```bash
# 进入容器
docker exec -it kafka bash

# 容器内的路径随镜像不同而不同（wurstmeister 风格一般是 /opt/kafka/bin）
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# 手动建一个 topic
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test --partitions 1 --replication-factor 1

# 生产 / 消费（发送后 Ctrl+C 退出）
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic test
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic test --from-beginning
```

从宿主机/其它机器连接时，用 `HOST_IP:9092`（例如 `192.168.0.200:9092`）作为 `bootstrap.servers`。

## 常见问题

1. **报 `pull access denied for kafka`**：本地没有 `kafka:latest` 镜像，见本文开头说明。
2. **能连上但消费报 `Connection to node 0 could not be established`**：`HOST_IP` 填错了（填成了 `127.0.0.1` 或已失效的旧 IP），改 `.env` 后重建。
3. **宿主机 2182 被占用**：改 `ports` 左边的 `2182`；注意 `KAFKA_ZOOKEEPER_CONNECT` 用的是容器网络内的服务名 `zookeeper:2181`，它不受宿主机映射影响。
4. **改了 `KAFKA_CREATE_TOPICS` 不生效**：该配置只在**首次创建数据目录**时生效（`/data/kafka` 已存在就不会再建），需要手动用 `kafka-topics.sh` 建，或清空 `/data/kafka` 重建（数据会丢）。
5. **想换成 KRaft 模式（不要 ZooKeeper）**：Kafka 3.3+ 支持，用官方 `apache/kafka` 镜像按官方文档配置即可，本目录不做改造。
