# Pulsar

Apache Pulsar **standalone** 单机版（消息队列），用于本地开发/调试：一个进程里同时跑 broker、本地 BookKeeper（存消息）和 Functions worker。

| 项目 | 说明 |
|------|------|
| 镜像 | `apachepulsar/pulsar`（版本见 `.env` 的 `PULSAR_VERSION`，默认 `4.2.4`） |
| 容器名 | `pulsar` |
| 启动方式 | `bin/pulsar standalone --advertised-address <HOST_IP>`（standalone 单机模式） |
| 客户端地址 | `pulsar://<宿主机IP>:6650`（二进制协议） |
| HTTP 地址 | <http://localhost:8085/admin/v2/>（Admin REST API）、`ws://localhost:8085/ws/v2/...`（WebSocket） |
| 数据目录 | `/data/pulsar/data`（元数据 + bookie 数据）、`/data/pulsar/logs`（日志） |
| 目录结构 | 只有 `.env` + `docker-compose.yml` + `Readme.md`，不挂配置文件（用镜像自带 `conf/standalone.conf` + 启动参数/环境变量） |

> 这是给本地开发用的**单机**形态（broker/BookKeeper/元数据都在一个容器里）。
> 生产要的是多 broker + 多 bookie + 独立元数据/代理，不是这个目录的目标。
>
> 顺带一提：Pulsar 的 topic 全名是 `persistent://public/default/<topic>`，standalone 默认 `allowAutoTopicCreation=true`
> （非分区 topic），所以**不用手动建 topic**，直接往一个不存在的 topic 生产消息就会自动创建。

## 使用到的端口

宿主机映射的端口（容器内保持 Pulsar 默认端口）：

| 端口 | 容器内 | 协议 | 用途 | 访问地址 / 说明 |
|------|:---:|------|------|-----------------|
| **6650** | 6650 | TCP | Pulsar 二进制协议 | `pulsar://192.168.110.141:6650`（Java/Python/Go/C++ SDK、`pulsar-client` 都连这里） |
| **8085** | 8080 | HTTP | Admin REST API + WebSocket + 健康检查 | <http://localhost:8085/admin/v2/brokers/health>、`ws://localhost:8085/ws/v2/producer/persistent/public/default/<topic>`（容器内是默认的 8080，宿主机侧改成 8085，**避开 nacos 占用的 8080**） |

容器内监听、但默认**不**映射到宿主机的端口（都是内部用的）：

| 容器内端口 | 用途 | 说明 |
|-----------|------|------|
| 3181 | 本地 BookKeeper bookie | 消息/ledger 实际写在这里，只有容器内部访问；要连它得自己加 `3181:3181` |
| 6750 | Functions worker | standalone 默认开启、和 broker 同进程；跑 `pulsar-admin functions` 用 HTTP 8085 就够了 |

> 和服务端端口比对一下别搞混：**客户端连 6650**（不是 8085）；8085 只是 HTTP/管理/WebSocket。
> 如果换成 3.x 镜像（或者在 `.env` 里加 `PULSAR_STANDALONE_USE_ZOOKEEPER=1`），standalone 还会起一个内嵌
> ZooKeeper（容器内 2181）和 stream storage（容器内 4181），需要的话自己加端口映射，见常见问题 7。

端口占用自查：

- `6650`、`8085` 在本仓库其它服务里都没有用到（8080 是 nacos 的，这里容器内虽然是 8080，但宿主机侧用的是 8085）；
- 3.x 下会多出 2181（ZooKeeper，和 kafka 的 2182 不是一回事）与 4181，本目录默认不映射这两个。

## 启动

```bash
cd Pulsar
docker compose up -d
docker compose ps                    # 等 STATUS 出现 (healthy)，首次启动约 30~60 秒
docker compose logs -f pulsar        # 日志里出现 "messaging service is ready" / "Started Pulsar Broker" 即成功
```

宿主机确认端口在监听：

```bash
ss -lntp | grep -E '6650|8085'
```

日志文件也在宿主机上，排查启动问题看这个：

```bash
tail -f /data/pulsar/logs/pulsar-standalone.log
```

## 验证

```bash
# 1) broker 健康检查（宿主机直接 curl，正常返回 ok）
curl -s http://localhost:8085/admin/v2/brokers/health

# 2) 生产 / 消费一条消息（用容器里自带的 CLI，宿主机不用装客户端）
docker exec -it pulsar bin/pulsar-client produce persistent://public/default/demo-topic -m "hello pulsar"
docker exec -it pulsar bin/pulsar-client consume persistent://public/default/demo-topic -s demo-sub -n 1

# 3) 管理命令（容器里的 pulsar-admin 默认连本机 8080，不用带地址）
docker exec -it pulsar bin/pulsar-admin brokers list standalone
docker exec -it pulsar bin/pulsar-admin topics list public/default
docker exec -it pulsar bin/pulsar-admin topics stats persistent://public/default/demo-topic

# 4) 宿主机用 REST API 看（示例：租户 / 命名空间 / topic 列表）
curl -s http://localhost:8085/admin/v2/tenants
curl -s http://localhost:8085/admin/v2/namespaces/public
curl -s http://localhost:8085/admin/v2/persistent/public/default
```

## 客户端接入

| 场景 | 地址 |
|------|------|
| Java / Python / Go / C++ SDK | `pulsar://192.168.110.141:6650` |
| Admin REST API / curl | `http://localhost:8085/admin/v2/...` |
| WebSocket 生产者 | `ws://192.168.110.141:8085/ws/v2/producer/persistent/public/default/demo-topic` |
| WebSocket 消费者 | `ws://192.168.110.141:8085/ws/v2/consumer/persistent/public/default/demo-topic/demo-sub` |

Java（官方 SDK）：

```xml
<dependency>
  <groupId>org.apache.pulsar</groupId>
  <artifactId>pulsar-client</artifactId>
  <version>4.2.4</version>
</dependency>
```

```java
try (PulsarClient client = PulsarClient.builder()
        .serviceUrl("pulsar://192.168.110.141:6650")
        .build()) {
    try (Producer<byte[]> producer = client.newProducer()
            .topic("persistent://public/default/demo-topic")
            .create()) {
        producer.send("hello pulsar".getBytes(StandardCharsets.UTF_8));
    }
    try (Consumer<byte[]> consumer = client.newConsumer()
            .topic("persistent://public/default/demo-topic")
            .subscriptionName("demo-sub")
            .subscribe()) {
        Message<byte[]> msg = consumer.receive(5, TimeUnit.SECONDS);
        System.out.println(new String(msg.getPayload(), StandardCharsets.UTF_8));
        consumer.acknowledge(msg);
    }
}
```

Spring Boot（spring-pulsar 的 `spring-boot-starter-pulsar`）：

```properties
spring.pulsar.client.service-url=pulsar://192.168.110.141:6650
```

Python：

```python
import pulsar
client = pulsar.Client('pulsar://192.168.110.141:6650')
producer = client.create_producer('persistent://public/default/demo-topic')
producer.send(b'hello pulsar')
client.close()
```

## 配置说明（.env）

改完执行 `docker compose up -d --force-recreate` 生效：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PULSAR_VERSION` | `4.2.4` | 镜像 tag（`apachepulsar/pulsar`；要内置 connector 就用 `apachepulsar/pulsar-all`） |
| `HOST_IP` | `192.168.110.141` | broker 通告地址（`--advertised-address`），必须是宿主机局域网 IP |
| `PULSAR_MEM` | `-Xms512m -Xmx1g -XX:MaxDirectMemorySize=1g` | JVM 内存（镜像默认是 `-Xms2g -Xmx2g -XX:MaxDirectMemorySize=4g`，已调小） |

不做外部配置的部分（都用镜像自带的 `conf/standalone.conf`）：

- `clusterName` 默认 `standalone`、租户 `public`、命名空间 `default`，都是 Pulsar 的固定默认；
- 容器内的 `brokerServicePort=6650`、`webServicePort=8080` 来自镜像的 `conf/standalone.conf`，**不要改容器内端口**，
  要换就改 `docker-compose.yml` 里 `ports` 的**左边**（如 `16650:6650`，客户端跟着改成 16650）；
- Topic 自动创建：`allowAutoTopicCreation=true`（非分区）；不想要就自己挂 `standalone.conf` 改。
- 事务默认是关的（`transactionCoordinatorEnabled=false`），要用事务得挂配置打开。

## 常见问题

1. **客户端能连上 6650，但生产/消费报 `Connection refused`、日志里 lookup 到 `localhost:6650`**

   这就是 `advertisedAddress` 没配对：broker 在 lookup 时会把「你接下来连我哪个地址」告诉客户端，
   standalone 默认通告 `localhost`，所以只有客户端也在**宿主机本机**时才刚好能用；
   局域网其它机器、或别的容器里的应用拿到 `localhost` 就连自己去了。

   本目录的做法是启动时传 `--advertised-address ${HOST_IP}`（取自 `.env`）。检查是否生效：

   ```bash
   docker inspect pulsar --format '{{.Config.Cmd}}'     # 应该能看到 --advertised-address 192.168.110.141
   grep -i advertis /data/pulsar/logs/pulsar-standalone.log | head
   ```

   改了 IP（换网络）记得改 `.env` 再 `docker compose up -d --force-recreate`。

2. **管理接口 8085 打不开 / 想换宿主机端口**

   - 容器刚起，等 30~60 秒：`docker compose logs -f pulsar`（健康检查有 60 秒 `start_period`，这期间显示 `health: starting` 是正常的）；
   - 确认映射：`docker compose ps` 里应有 `0.0.0.0:8085->8080/tcp`；
   - 宿主机 8085 也被占用就改 `ports` 左边（如 `9085:8080`），容器内保持 8080 不动；
   - 要改**容器内**端口（一般不用）：把镜像的 conf 拷出来改 `webServicePort`，挂进容器并加启动参数 `-c /pulsar/conf/xxx.conf`。

3. **为什么用 root 跑容器（`user: "0:0"`）/ 数据目录 Permission denied**

   镜像默认用 uid **10000**（`USER 10000`）运行，而宿主机 `/data/pulsar/data`、`/data/pulsar/logs` 是 Docker 以
   **root:root 755** 创建的，uid 10000 没有写权限 → 容器起来就报权限错误。两种解法：

   - 保持现在的 `user: "0:0"`（简单，本地开发够用）；
   - 想按镜像默认的非 root 跑：

     ```bash
     sudo mkdir -p /data/pulsar/data /data/pulsar/logs
     sudo chown -R 10000:0 /data/pulsar/data /data/pulsar/logs
     # 然后删掉 docker-compose.yml 里的 user: "0:0" 那两行
     docker compose up -d --force-recreate
     ```

4. **数据存在哪 / 怎么彻底重置**

   | 路径 | 内容 |
   |------|------|
   | `/data/pulsar/data/standalone/bookkeeper` | bookie 数据（消息 ledger 真正落盘的地方） |
   | `/data/pulsar/data/metadata` | 元数据（4.x 默认 RocksDB：tenant/namespace/topic/订阅等） |
   | `/data/pulsar/logs/pulsar-standalone.log` | broker 主日志 |
   | `/data/pulsar/logs/*.log` | GC 日志、bookkeeper 日志等 |

   重置（**先停容器**，否则元数据和数据可能删出不一致）：

   ```bash
   docker compose down
   sudo rm -rf /data/pulsar/data/* /data/pulsar/logs/*     # Windows(Docker Desktop) 见第 11 条
   docker compose up -d
   ```

   也可以让 Pulsar 自己清：`docker compose run --rm pulsar bin/pulsar standalone --wipe-data`（会清 ZK/BK 旧数据，
   只适合调试）。

5. **topic 或消息「自己没了」**

   standalone 用的 `conf/standalone.conf` 里这几个默认值要心里有数：

   - `brokerDeleteInactiveTopicsEnabled=true` + `brokerDeleteInactiveTopicsFrequencySeconds=60`
     → **没有任何订阅的空 topic，60 秒一轮的检查里会被自动删除**（删掉后你再发消息会重新自动创建，看起来像「消息丢了」）；
   - `defaultRetentionTimeInMinutes=0` + `defaultRetentionSizeInMB=0`
     → 没有设置 retention 策略的命名空间，消息被所有订阅 ack 完就删，不会留历史；
   - `systemTopicEnabled=true` → 会有 `__change_events`、`__transaction_buffer_snapshot` 之类的系统 topic，属正常。

   要留住消息/关掉自动删 topic：把镜像的 `conf/standalone.conf` 拷贝到 `config/`、改这几项，再挂载并用 `-c` 指定。

6. **容器内存不够 / 报 `Direct buffer memory`**

   `PULSAR_MEM` 里的 `-XX:MaxDirectMemorySize` 不是随便填的：BookKeeper 的读写缓存大小由它推导
   （约 `MaxDirectMemorySize / (1 + bookie 数) / 4`，默认 1 个 bookie → 各占 1/8），同时 Netty 还用直接内存。
   报 `OutOfDirectMemoryError` / `Direct buffer memory` 就把它调大（如 `-XX:MaxDirectMemorySize=2g`）；
   只是堆内存紧张就调小 `-Xmx`。

7. **ZooKeeper 呢？4.x 的 standalone 怎么只有 BookKeeper**

   Pulsar 4.x 按 PIP-117 换了默认元数据存储：standalone 直接用 **RocksDB**（`data/metadata`）当元数据存储，
   **不再启动 ZooKeeper**，所以没有 2181。以下情况才会有 ZK（容器内 2181，stream storage 4181）：

   - 用 3.x 及更早的镜像；
   - 显式设置环境变量 `PULSAR_STANDALONE_USE_ZOOKEEPER=1`（想让元数据继续存 ZK 时用）；
   - `data/standalone/zookeeper` 目录已存在（检测到旧数据就沿用 ZK 模式）。

   这两种模式不要共用同一份 `/data/pulsar/data`，切模式前先清空（见第 4 条）。

8. **有没有 Web 管理界面（像 RocketMQ Dashboard 那种）**

   官方镜像是纯后端，没有 UI；常用的是独立的 `apachepulsar/pulsar-manager`。要的话在
   `docker-compose.yml` 里追加（端口选了没冲突的 9527/7750，需要一次性初始化管理员账号）：

   ```yaml
     pulsar-manager:
       image: apachepulsar/pulsar-manager:v0.4.0
       container_name: pulsar-manager
       restart: always
       environment:
         - SPRING_CONFIGURATION_FILE=/pulsar-manager/pulsar-manager/application.properties
       ports:
         - 9527:9527
         - 7750:7750
   ```

   ```bash
   CSRF_TOKEN=$(curl -s http://localhost:7750/pulsar-manager/csrf-token)
   curl -H "X-XSRF-TOKEN: $CSRF_TOKEN" -H "Cookie: XSRF-TOKEN=$CSRF_TOKEN" \
        -H "Content-Type: application/json" -X PUT http://localhost:7750/pulsar-manager/users/superuser \
        -d '{"name":"admin","password":"123456","description":"admin","email":"admin@example.com"}'
   # 然后打开 http://localhost:9527 ，登录后在「Service URL」里填 http://pulsar:8080（容器内端口）
   ```

   日常看队列状态其实用 `docker exec -it pulsar bin/pulsar-admin` + REST API 就够了。

9. **想跑 Functions / 内置 Connector**

   镜像是普通版（`apachepulsar/pulsar`），能跑 Functions（Python 运行时已内置），但**没有内置 source/sink connector**；
   要内置 connector 就把 `.env` 的镜像换成 `apachepulsar/pulsar-all`。
   另外函数包/依赖目录（`/pulsar/instances`、`/pulsar/download`）默认没挂到宿主机，重启容器会重新下载依赖——
   介意的话自己加两个挂载。

10. **`PULSAR_STANDALONE_USE_ZOOKEEPER` / 换版本要注意什么**

    4.x ↔ 3.x 的元数据存储方式不同（RocksDB vs ZooKeeper），**不要拿同一份 `/data/pulsar/data` 来回切**。
    换版本：改 `.env` 的 `PULSAR_VERSION` → `docker compose down` → 清空 `/data/pulsar/data` → `up -d`。
    报 `manifest unknown` 就是 tag 不存在，去 Docker Hub 的 `apachepulsar/pulsar` 页面挑一个。

11. **Windows（Docker Desktop）上怎么删数据目录**

    没有 Linux 的 `sudo rm -rf`，用一次性容器删：

    ```bash
    docker run --rm -v /data/pulsar/data:/data alpine sh -c "rm -rf /data/*"
    ```

12. **能当生产用吗 / 能不能加一个从副本**

    不能。standalone 单机单副本（`managedLedgerDefaultEnsembleSize=1` 之类都是按单机写死的），重启会短暂不可用，
    没有多副本容灾。生产要么用官方 Helm/多节点部署，要么在业务侧容忍这台单机挂掉的场景。
    本地要「多一点真实感」可以再加一个 broker 组成集群，那已经超出这个目录的范围了。
