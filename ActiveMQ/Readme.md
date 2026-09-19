# ActiveMQ

Apache ActiveMQ **Classic** 单机版（消息队列），用于本地开发/调试。

| 项目 | 说明 |
|------|------|
| 镜像 | `apache/activemq-classic`（版本见 `.env` 的 `ACTIVEMQ_VERSION`，默认 `6.1.6`；Java 8/11 的客户端可以换成 `5.18.x`） |
| 容器名 | `activemq` |
| 默认协议 | OpenWire（61616）+ AMQP + STOMP + MQTT + WebSocket |
| Web 控制台 | <http://localhost:8161/>，账号见 `.env`（默认 `admin` / `123456`） |
| 数据目录 | `/data/activemq/data`（KahaDB 消息数据 + `activemq.log`、`audit.log`） |
| 目录结构 | 只有 `.env` + `docker-compose.yml` + `Readme.md`，不需要额外配置文件（全部用镜像默认配置 + 环境变量） |

> 这里说的是 **ActiveMQ Classic**（老牌 5.x/6.x 那条线，OpenWire 协议）。
> 新一代的 **ActiveMQ Artemis**（`apache/activemq-artemis`，端口 61616/8161 类似但配置完全不同）不在此目录范围内。

## 使用到的端口

宿主机映射的端口（**故意避开**本仓库其它服务已占用的端口，容器内仍是 ActiveMQ 默认端口）：

| 端口 | 容器内 | 协议 | 用途 | 访问地址 / 说明 |
|------|:---:|------|------|-----------------|
| **61616** | 61616 | TCP | OpenWire（默认、最常用） | `tcp://<宿主机IP>:61616`（Java/JMS、Python、.NET、Go 客户端都连这个） |
| **8161** | 8161 | HTTP | Web 控制台（Jetty） | <http://localhost:8161/>（Queues / Topics / Connections / 发消息） |
| **61613** | 61613 | TCP | STOMP | `stomp://<宿主机IP>:61613`（`stomp.py`、`@stomp/stompjs` 等） |
| **61614** | 61614 | TCP | STOMP over WebSocket | `ws://<宿主机IP>:61614`（浏览器端 JS 客户端） |
| **5673** | 5672 | TCP | AMQP 1.0 | `amqp://<宿主机IP>:5673` —— 宿主机侧改名，避开 `rabbitmq` 的 5672 |
| **11883** | 1883 | TCP | MQTT 3.1.1 | `tcp://<宿主机IP>:11883` —— 宿主机侧改名，避开 `mosquitto` / `mqtt`(emqx) 的 1883 |

端口占用自查：

- `8161`（控制台）、`61616`、`61613`、`61614` 在本仓库其它服务里都没有用到；
- `5673`、`11883` 是为了避开 `rabbitmq`（5672）和 `mosquitto`/`mqtt`（1883）**特意换的宿主机端口**；
  容器内依然是 5672 / 1883，所以 ActiveMQ 自身配置不用改，只要客户端连的时候用 5673 / 11883。

容器内不监听额外端口：默认 `activemq.xml` 的 `managementContext createConnector="false"`，所以没有 JMX 端口；
`8161` 就是控制台本身（不像 RocketMQ 那样还分 NameServer/Broker 多个端口）。

## 启动

```bash
cd ActiveMQ
docker compose up -d
docker compose ps
docker compose logs -f activemq          # 看到 "ActiveMQ ... started" 即成功（首次启动约 5~15 秒）
```

宿主机确认端口都在监听（Linux）：

```bash
ss -lntp | grep -E '61616|8161|61613|61614|5673|11883'
```

确认数据目录挂对了（里面有 `kahadb/`、`activemq.log`）：

```bash
docker exec -it activemq ls -l /opt/apache-activemq/data
```

## 验证

```bash
# 控制台（浏览器打开，用 .env 里的账号密码登录）
http://localhost:8161/

# 控制台首页能不能出 HTML（401 表示需要登录，说明服务是活的）
curl -sI http://localhost:8161/admin/ | head -1

# 在控制台里：Queues -> 新建队列 -> Send To 发一条消息 -> 点队列名 Browse 看消息
```

用客户端连（宿主机上的应用）：

| 协议 | 连接地址示例 |
|------|-------------|
| OpenWire（JMS） | `tcp://192.168.110.141:61616` |
| STOMP | `tcp://192.168.110.141:61613` |
| WebSocket | `ws://192.168.110.141:61614` |
| AMQP 1.0 | `amqp://192.168.110.141:5673` |
| MQTT | `tcp://192.168.110.141:11883` |

Java（JMS / OpenWire）示例：

```xml
<!-- Java 17+ 用 6.x 客户端；Java 8/11 用 5.18.x -->
<dependency>
  <groupId>org.apache.activemq</groupId>
  <artifactId>activemq-client</artifactId>
  <version>6.1.6</version>
</dependency>
```

```java
ConnectionFactory factory = new ActiveMQConnectionFactory("tcp://192.168.110.141:61616");
try (Connection conn = factory.createConnection()) {
    conn.start();
    Session session = conn.createSession(false, Session.AUTO_ACKNOWLEDGE);
    Queue queue = session.createQueue("demo.queue");
    try (MessageProducer producer = session.createProducer(queue)) {
        producer.send(session.createTextMessage("hello activemq"));
    }
    try (MessageConsumer consumer = session.createConsumer(queue)) {
        System.out.println(((TextMessage) consumer.receive(2000)).getText());
    }
}
```

Spring Boot（`spring-boot-starter-activemq`）：

```properties
spring.activemq.broker-url=tcp://192.168.110.141:61616
```

> `broker` 默认没开鉴权（`activemq.xml` 里 `simpleAuthenticationPlugin` 是注释掉的），所以连 61616 不用带账号密码。
> 只把端口暴露在开发机内网时没问题；要给别人连就打开鉴权（见常见问题 8）。

## 配置说明（.env）

改完执行 `docker compose up -d --force-recreate` 生效：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ACTIVEMQ_VERSION` | `6.1.6` | 镜像 tag（`apache/activemq-classic`；老客户端可用 `5.18.7`） |
| `ACTIVEMQ_ADMIN_LOGIN` | `admin` | Web 控制台用户名 |
| `ACTIVEMQ_ADMIN_PASSWORD` | `123456` | Web 控制台密码 |
| `ACTIVEMQ_OPTS_MEMORY` | `-Xms256m -Xmx1g` | JVM 内存，内存紧张的机器可以调小 |

不做外部配置的部分（都用镜像默认值，改起来要挂配置文件）：

- `brokerName` 默认 `localhost`，控制台标题里显示的就是它；
- 各协议的端口（61616/5672/61613/1883/61614）都在镜像自带的 `conf/activemq.xml` 里，容器内不建议改，
  宿主机侧要换端口就改 `docker-compose.yml` 里 `ports` 的**左边**（如 `2616:61616`）；
- 队列/主题的持久化策略：默认 `KahaDB`，数据落在 `/data/activemq/data/kahadb`。

## 常见问题

1. **控制台登录不上 / 账号密码不是 `.env` 里的**

   控制台账号来自镜像内的 `conf/jetty-realm.properties`。`.env` 里的 `ACTIVEMQ_ADMIN_LOGIN/PASSWORD` 是官方镜像的
   环境变量，可用下面命令确认是否生效：

   ```bash
   docker exec -it activemq cat /opt/apache-activemq/conf/jetty-realm.properties
   ```

   如果文件里还是 `admin: admin, admin`，说明这个镜像版本不认那两个环境变量，直接改文件（改完重启，重建容器会丢）：

   ```bash
   docker exec -it activemq sed -i 's/^admin:.*/admin: 123456, admin/' /opt/apache-activemq/conf/jetty-realm.properties
   docker restart activemq
   ```

   想持久化就把改好的文件拷出来挂进去（同时把 `.env` 里的 `ACTIVEMQ_ADMIN_*` 注释掉，避免两处配置打架）：

   ```bash
   docker cp activemq:/opt/apache-activemq/conf/jetty-realm.properties ./config/jetty-realm.properties
   # docker-compose.yml 的 volumes 里加：
   #   - ./config/jetty-realm.properties:/opt/apache-activemq/conf/jetty-realm.properties:ro
   docker compose up -d --force-recreate
   ```

2. **控制台打不开（8161）**

   - 容器刚起，等 10 秒左右再看：`docker compose logs -f activemq`；
   - 确认映射在：`docker compose ps`（`0.0.0.0:8161->8161/tcp`）；
   - 8161 被占用就改 `ports` 左边，如 `8261:8161`；
   - 容器内控制台端口是 `conf/jetty.xml` 里的 8161，改容器内端口要挂 `jetty.xml`，一般不需要。

3. **为什么 AMQP 是 5673、MQTT 是 11883**

   容器内就是标准端口 5672 / 1883，只是宿主机上这两个端口已经被本仓库的 `rabbitmq` 和 `mosquitto`/`mqtt` 占了，
   所以 `ports` 写成 `5673:5672`、`11883:1883`。客户端连宿主机时用 **5673 / 11883**，
   连接字符串里的协议不用改（依然是 `amqp://` / `mqtt://`）。

4. **消息重启后还在吗 / 数据在哪**

   在 `/data/activemq/data`（`kahadb/` 是消息持久化目录，`activemq.log`、`audit.log` 是日志）。
   没有持久化的消息（非持久化消息、临时队列）重启会丢，这是 JMS 语义决定的。
   清空所有数据（**先停容器**）：

   ```bash
   docker compose down
   sudo rm -rf /data/activemq/data/*          # Windows(Docker Desktop) 见第 10 条
   docker compose up -d
   ```

5. **数据没落到 `/data/activemq/data`（挂载路径不对）**

   不同镜像版本的家目录可能不是 `/opt/apache-activemq`（软链）而是带版本号的目录。自查：

   ```bash
   docker exec -it activemq ls -l /opt
   docker exec -it activemq sh -c 'echo $ACTIVEMQ_HOME; ls -l $ACTIVEMQ_HOME/data | head'
   ```

   如果实际路径不是 `/opt/apache-activemq/data`（例如 `/opt/apache-activemq-6.1.6/data`），
   把 `docker-compose.yml` 里的挂载改成实际路径后重建即可（日志同理，默认都在 `data` 目录下）。

6. **容器内存不够 / 被系统 OOM kill**

   把 `.env` 的 `ACTIVEMQ_OPTS_MEMORY` 调小（如 `-Xms128m -Xmx512m`）后重建；
   KahaDB 有页缓存，`-Xmx` 也别设得太小，512m 以下不太推荐。

7. **61616 连不上**

   - 确认用的是 **61616**（不是控制台的 8161，也不是 AMQP/MQTT 的 5673/11883）；
   - 确认 `ports` 里映射了 61616，且宿主机防火墙放行；
   - 应用如果跑在容器里，直接连宿主机 IP 一般没问题（走映射端口）；也可以把应用容器接到 `activemq_default`
     网络后用服务名 `activemq:61616`。

8. **想给 broker 开鉴权（默认任何人都能连 61616）**

   默认 `activemq.xml` 里 `<simpleAuthenticationPlugin>` 是注释状态。要开启：把镜像的 `conf/activemq.xml`
   拷到宿主机（`docker cp activemq:/opt/apache-activemq/conf/activemq.xml ./config/`），
   打开 `simpleAuthenticationPlugin` 并配上 users/groups，再按第 1 条的方式挂载进去重建。
   注意：这属于**整文件覆盖**镜像自带的配置，升级镜像时要重新拷一份比对。

9. **想换 ActiveMQ 版本 / 从 5.x 升到 6.x**

   改 `.env` 的 `ACTIVEMQ_VERSION` 后 `docker compose up -d`。6.x 要求 Java 17（服务端镜像自带，
   客户端 SDK 也要 17+）；客户端还在 Java 8/11 就继续用 `5.18.x`。跨大版本升级前建议先备份
   `/data/activemq/data`，KahaDB 的格式在两个大版本间可能有差异。

10. **Windows（Docker Desktop）上怎么删数据目录**

    没有 Linux 的 `sudo rm -rf`，用一次性容器删：

    ```bash
    docker run --rm -v /data/activemq/data:/data alpine sh -c "rm -rf /data/*"
    ```

11. **报 `manifest unknown` / `pull access denied`**

    镜像 tag 不存在（`.env` 的 `ACTIVEMQ_VERSION` 写错或太新/太旧）或拉不动 Docker Hub。
    去 Docker Hub 的 `apache/activemq-classic` 页面挑一个存在的 tag（也可以先用 `latest`），
    内网拉不动就换成自己的镜像仓库地址（`image:` 那一行）。
