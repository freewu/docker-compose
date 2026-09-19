# RocketMQ

Apache RocketMQ 单机版：**NameServer + Broker + Dashboard（Web 控制台）**，用于本地开发/调试消息队列。

| 项目 | 说明 |
|------|------|
| 镜像 | `apache/rocketmq`（NameServer 与 Broker 是**同一个**镜像，版本见 `.env` 的 `ROCKETMQ_VERSION`，默认 `5.3.2`） |
| 控制台镜像 | `apacherocketmq/rocketmq-dashboard`（版本见 `.env` 的 `ROCKETMQ_DASHBOARD_VERSION`，默认 `2.0.0`） |
| 容器名 | `rocketmq-namesrv`、`rocketmq-broker`、`rocketmq-dashboard` |
| 集群名 / Broker 名 | `DefaultCluster` / `broker-a`（单机一个 master，`brokerId = 0`） |
| 数据目录 | `/data/rocketmq/namesrv/logs`、`/data/rocketmq/broker/{logs,store}` |
| 配置文件 | `config/broker.conf`（**模板**，启动时把 `@HOST_IP@` 换成 `.env` 的 `HOST_IP`） |

## 使用到的端口

宿主机映射的端口（本仓库其它服务都没有用到，不会冲突）：

| 端口 | 容器内 | 协议 | 用途 | 从宿主机/客户端怎么用 |
|------|:---:|------|------|----------------------|
| **9876** | 9876 | TCP | NameServer（路由中心） | SDK 的 `namesrvAddr` 填 `<宿主机IP>:9876` |
| **10911** | 10911 | TCP | Broker 主端口（remoting，收发消息） | 一般不用手填，客户端从 NameServer 拿到 |
| **10909** | 10909 | TCP | Broker **VIP 通道**（= 10911 − 2） | 官方 Java 客户端**默认走这个**，所以必须映射 |
| **10912** | 10912 | TCP | Broker HA 主从同步（= 10911 + 1） | 单机用不到，先映射着，以后加从节点不用改 |
| **8180** | 8080 | HTTP | Dashboard 控制台 | <http://localhost:8180/>（宿主机 8080 已被 nacos 占用，所以换成 8180） |

只在容器内监听、**不映射**到宿主机的端口（不会和宿主机其它服务冲突）：

| 端口 | 用途 | 说明 |
|------|------|------|
| 8080 | Dashboard 容器内端口 | 宿主机侧映射成 8180 |
| 8081 | Broker 的 gRPC 代理端口 | RocketMQ 5.x 打开 `enableProxy = true` 后才有；要用 gRPC 客户端（`rocketmq-client-java`、Spring Cloud Stream RocketMQ 5.x）时把它映射出来 |

> ⚠️ 端口之间有**固定偏移关系**：VIP 通道 = 主端口 − 2（10909），HA 端口 = 主端口 + 1（10912）。
> 想换 broker 端口就改 `listenPort`（要在 `config/broker.conf` 里加），或者只改宿主机侧映射；
> 但 `10911:10911` 这种一一对应最省事，改了左边记得同步客户端/防火墙。

## 必填：HOST_IP（宿主机局域网 IP）

Broker 会把自己「认为的地址」（`brokerIP1`）注册到 NameServer，客户端从 NameServer 查到后**直接连这个地址**，
所以它必须是**宿主机局域网 IP**，不能是 `127.0.0.1`，也不能是容器 IP / 容器名：

- 填 `127.0.0.1`：宿主机上的客户端连的是自己（可能连得上），但其它机器 / 其它容器连不上；
- 填容器 IP（`172.x.x.x`）：**只有同一个 docker 网络里的容器**能用，宿主机上的应用连不上；
- 填错 IP 的症状：`connect to <ip>:10911 failed`、`sendDefaultImpl call timeout`、控制台看不到 Broker 详情。

配置在 `rocketmq/.env`：

```dotenv
HOST_IP=192.168.110.141
```

探测本机当前 IP（不动任何文件，只打印）：

```bash
../redis-cluster/set-host-ip.sh --print
```

改完重建 broker（`brokerIP1` 是启动时渲染进配置的，必须重建容器）：

```bash
docker compose up -d --force-recreate broker
```

> `config/broker.conf` 里写的是 `@HOST_IP@` 占位符，compose 启动 broker 时执行
> `sed "s/@HOST_IP@/$HOST_IP/g" ... > /home/rocketmq/broker.conf` 再 `sh mqbroker -c ...`。
> 想看渲染后的真实配置：`docker exec rocketmq-broker cat /home/rocketmq/broker.conf`。
> 不想用占位符也行，直接把 `brokerIP1 = @HOST_IP@` 改成写死的 IP（那样就不用管 `HOST_IP` 了）。

## 目录结构

```
rocketmq/
├── .env                 # 镜像版本、HOST_IP（brokerIP1）、NameServer/Broker 的 JVM 内存
├── docker-compose.yml   # namesrv + broker + dashboard
├── config/
│   └── broker.conf      # Broker 配置模板（brokerIP1 = @HOST_IP@ 由 .env 注入）
└── Readme.md
```

宿主机数据目录：

| 宿主机路径 | 容器内路径 | 内容 |
|-----------|-----------|------|
| `/data/rocketmq/namesrv/logs` | `/home/rocketmq/logs` | NameServer 日志 |
| `/data/rocketmq/broker/logs` | `/home/rocketmq/logs` | Broker 日志（业务日志 + `store.log`） |
| `/data/rocketmq/broker/store` | `/home/rocketmq/store` | **消息数据**：`commitlog/`、`consumequeue/`、`index/`、`checkpoint` 等 |

## 启动

```bash
cd rocketmq
docker compose up -d
docker compose ps                 # 三个容器都应是 Up
docker compose logs -f broker     # 看到 "The broker[broker-a, <HOST_IP>:10911] boot success" 即成功
```

启动顺序：`namesrv` → `broker`（`depends_on` 只保证先启动 NameServer）、`dashboard`。

## 验证

```bash
# 1. 看集群里有哪些 broker（能列出 DefaultCluster / broker-a / 10911 就说明注册成功）
docker exec -it rocketmq-namesrv sh mqadmin clusterList -n 127.0.0.1:9876
docker exec -it rocketmq-broker  sh mqadmin clusterList -n namesrv:9876

# 2. 看 broker 运行状态（-b 用注册的地址，即 <HOST_IP>:10911）
docker exec -it rocketmq-broker sh mqadmin brokerStatus -n namesrv:9876 -b 192.168.110.141:10911

# 3. 看 / 建 topic（默认 autoCreateTopicEnable = true，发消息会自动建）
docker exec -it rocketmq-broker sh mqadmin topicList -n namesrv:9876
docker exec -it rocketmq-broker sh mqadmin updateTopic -n namesrv:9876 -c DefaultCluster -t TopicTest

# 4. 命令行发一条消息（消费用 SDK 或控制台，见下面示例）
docker exec -it rocketmq-broker sh mqadmin sendMessage -n namesrv:9876 -t TopicTest -p "hello rocketmq"
```

Web 控制台：<http://localhost:8180/>（看 Cluster / Topic / Consumer，也能直接发消息）。
控制台连的是容器网络里的 `namesrv:9876`，Broker 则是通过 `brokerIP1 = <HOST_IP>` 访问，所以宿主机 IP 必须可达。

## 客户端接入（宿主机上的应用）

NameServer 地址统一填 `<HOST_IP>:9876`（如 `192.168.110.141:9876`）。

Maven：

```xml
<dependency>
  <groupId>org.apache.rocketmq</groupId>
  <artifactId>rocketmq-client</artifactId>
  <version>5.3.2</version>
</dependency>
```

Java（生产者）：

```java
DefaultMQProducer producer = new DefaultMQProducer("please_rename_unique_group_name");
producer.setNamesrvAddr("192.168.110.141:9876");   // 宿主机局域网 IP，不是 127.0.0.1
// 官方客户端默认走 VIP 通道（10911 - 2 = 10909），本目录已映射；遇到问题可关掉：
// producer.setVipChannelEnabled(false);
producer.start();
Message msg = new Message("TopicTest", "TagA", "hello rocketmq".getBytes(StandardCharsets.UTF_8));
SendResult result = producer.send(msg);
System.out.println(result);
producer.shutdown();
```

Java（消费者）：

```java
DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("please_rename_unique_group_name");
consumer.setNamesrvAddr("192.168.110.141:9876");
consumer.subscribe("TopicTest", "*");
consumer.registerMessageListener((MessageListenerConcurrently) (msgs, ctx) -> {
    msgs.forEach(m -> System.out.println(new String(m.getBody(), StandardCharsets.UTF_8)));
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
});
consumer.start();
```

Spring Boot（`rocketmq-spring-boot-starter` 2.3.x）：

```properties
rocketmq.name-server=192.168.110.141:9876
rocketmq.producer.group=my-producer-group
```

> 应用如果也跑在 Docker 里：把容器接入本目录的网络（`docker network connect rocketmq-net <容器>`），
> `namesrvAddr` 用 `rocketmq-namesrv:9876`（或服务名 `namesrv:9876`）；如果仍用 `HOST_IP:9876` 也可以（走宿主机映射端口）。

## 配置说明（.env 与 broker.conf）

`.env`（改完 `docker compose up -d --force-recreate` 生效）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ROCKETMQ_VERSION` | `5.3.2` | `apache/rocketmq` 镜像 tag（NameServer/Broker 共用） |
| `ROCKETMQ_DASHBOARD_VERSION` | `2.0.0` | 控制台镜像 tag |
| `HOST_IP` | `192.168.110.141` | 宿主机局域网 IP，注入到 `brokerIP1`（**必填**） |
| `NAMESRV_JAVA_OPT_EXT` | `-Xms512m -Xmx512m -Xmn256m` | NameServer JVM 参数（镜像默认 4g） |
| `BROKER_JAVA_OPT_EXT` | `-Xms1g -Xmx1g -Xmn512m` | Broker JVM 参数（镜像默认 8g） |

> 两个 JVM 变量通过镜像支持的 `JAVA_OPT_EXT` 环境变量传入（它会被追加到镜像默认的 `JAVA_OPT` 后面，所以后面的 `-Xmx` 生效）。

`config/broker.conf`（改完 `docker compose up -d --force-recreate broker` 生效）：

| 配置项 | 值 | 说明 |
|--------|----|------|
| `brokerClusterName` / `brokerName` | `DefaultCluster` / `broker-a` | 集群名 / broker 名 |
| `brokerId` | `0` | `0` 表示 master |
| `brokerIP1` | `@HOST_IP@` | 对外通告地址，由 `.env` 的 `HOST_IP` 注入 |
| `brokerRole` | `ASYNC_MASTER` | 单机主节点（无从节点） |
| `flushDiskType` | `ASYNC_FLUSH` | 异步刷盘，开发环境吞吐优先；要更强可靠性改 `SYNC_FLUSH` |
| `deleteWhen` / `fileReservedTime` | `04` / `48` | 凌晨 4 点清理，文件保留 48 小时 |
| `autoCreateTopicEnable` | `true` | 自动创建 Topic（生产建议改 `false`） |

## 常见问题

1. **发送/消费报 `sendDefaultImpl call timeout`、`connect to <ip>:10911 failed`**

   `brokerIP1` 不可达。检查 `.env` 的 `HOST_IP` 是不是**宿主机局域网 IP**（`set-host-ip.sh --print` 能探测），
   改完执行 `docker compose up -d --force-recreate broker`；
   用 `docker exec rocketmq-broker cat /home/rocketmq/broker.conf` 确认渲染后的 `brokerIP1` 正确。

2. **控制台能打开，但 Broker/Topic 详情页报错或空白**

   控制台也要通过 `brokerIP1` 访问 Broker：确认 `HOST_IP` 从容器内可达（一般走映射端口没问题），
   以及 10909/10911 都映射了。若客户端提示 VIP 通道问题，可在 `docker-compose.yml` 的 `JAVA_OPTS` 里加
   `-Dcom.rocketmq.sendMessageWithVIPChannel=false`（Java 客户端对应 `setVipChannelEnabled(false)`）后重启控制台。

3. **容器启动就退出 / 被 OOM killed（内存不够）**

   镜像默认 JVM 是 NameServer 4g、Broker 8g。在 `.env` 里把 `NAMESRV_JAVA_OPT_EXT` / `BROKER_JAVA_OPT_EXT` 调小
   （默认已经是 `512m` / `1g`），然后 `docker compose up -d --force-recreate`。
   另外 Broker 还需要堆外内存（DirectMemory），机器内存很小时给 `-Xmx1g` 就够了。

4. **日志/数据目录报 `Permission denied`**

   本目录已经给 `namesrv` / `broker` 加了 `user: "0:0"`（以 root 运行），宿主机 `/data/rocketmq` 由 Docker 以 root 创建也能写。
   想改回非 root（镜像默认用户是 `rocketmq`，uid/gid `3000`）：

   ```bash
   docker run --rm -v /data/rocketmq:/data alpine chown -R 3000:3000 /data   # Windows 见第 10 条
   ```

   然后把 `docker-compose.yml` 里两处 `user: "0:0"` 删掉。

5. **宿主机 8180（控制台）被占用，想换端口**

   改 `docker-compose.yml` 里 `dashboard.ports` 左边的端口即可（容器内固定 8080），例如 `8880:8080`。
   9876（NameServer）要跟着改客户端配置；broker 端口一般不用动。

6. **想清空所有消息、恢复出厂**

   ```bash
   docker compose down
   sudo rm -rf /data/rocketmq/*        # Windows(Docker Desktop) 见第 10 条
   docker compose up -d
   ```

   只清消息、保留日志：删 `/data/rocketmq/broker/store` 下的 `commitlog`、`consumequeue`、`index`、`checkpoint`、`abort`（**必须停容器再删**）。

7. **想加从节点 / 搭集群**

   本目录是单机单 master。加从节点要在同一个 compose 里再加一个 broker 服务（`brokerId = 1`、`brokerRole = SLAVE`、
   `brokerIP2 = <master 可达地址>`），同时给每个 broker 改 `listenPort`（如 master 10911、slave 10921，HA 端口随之变化），
   并把端口都映射出来；具体可参考官方 [rocketmq-docker](https://github.com/apache/rocketmq-docker) 的多主多从模板。

8. **想用 gRPC（5.x 新协议）客户端**

   在 `config/broker.conf` 里加 `enableProxy = true`，并把 `docker-compose.yml` 里 broker 的 `8081:8081` 取消注释（当前没有映射），
   然后 `docker compose up -d --force-recreate broker`。老客户端（remoting）不受影响。

9. **想换版本**

   改 `.env` 的 `ROCKETMQ_VERSION`（如 `4.9.7` / `5.1.4` / `5.3.3`）后 `docker compose up -d`。
   4.9.x 的 `broker.conf` 同样兼容本目录的模板；控制台 2.0.0 也支持 4.9/5.x。
   换版本后建议清一次 `/data/rocketmq/broker/store`（不同版本存储格式不完全兼容）。

10. **Windows（Docker Desktop）上怎么删数据目录**

    没有 Linux 的 `sudo rm -rf`，用一次性容器删：

    ```bash
    docker run --rm -v /data/rocketmq:/data alpine sh -c "rm -rf /data/*"
    ```

11. **`mqadmin` 在哪、有哪些常用命令**

    在 NameServer/Broker 容器里直接可用（`sh mqadmin <子命令>`，已在家目录）：

    ```bash
    docker exec -it rocketmq-broker sh mqadmin clusterList   -n namesrv:9876
    docker exec -it rocketmq-broker sh mqadmin topicList     -n namesrv:9876
    docker exec -it rocketmq-broker sh mqadmin topicStatus   -n namesrv:9876 -t TopicTest
    docker exec -it rocketmq-broker sh mqadmin consumerProgress -n namesrv:9876
    docker exec -it rocketmq-broker sh mqadmin deleteTopic   -n namesrv:9876 -c DefaultCluster -t TopicTest
    ```

12. **`docker compose ps` 里 broker 一直重启**

    先看日志：`docker compose logs --tail=100 broker`。
    常见原因是 `HOST_IP` 没配（compose 会直接报 `请在 rocketmq/.env 中配置 HOST_IP`）、
    宿主机 10911/10909/10912 被占用（如本机已装 RocketMQ），或 JVM 内存太大被系统杀掉。
