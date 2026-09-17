# Redis Cluster 集群（3 主 3 从）

```
# 端口

服务名称           | 客户端端口 | 集群总线端口 | 数据目录                          | 说明
------------------ | --------- | ----------- | -------------------------------- |------------------
redis-node-1       | 7001      | 17001       | /data/redis-cluster/node-7001    | 主节点1
redis-node-2       | 7002      | 17002       | /data/redis-cluster/node-7002    | 主节点2
redis-node-3       | 7003      | 17003       | /data/redis-cluster/node-7003    | 主节点3
redis-node-4       | 7004      | 17004       | /data/redis-cluster/node-7004    | 从节点1 (node-1 的副本)
redis-node-5       | 7005      | 17005       | /data/redis-cluster/node-7005    | 从节点2 (node-2 的副本)
redis-node-6       | 7006      | 17006       | /data/redis-cluster/node-7006    | 从节点3 (node-3 的副本)
redis-cluster-init | -         | -           | -                                | 一次性初始化集群，执行完自动退出(正常现象)
set-host-ip.sh     | -         | -           | -                                | 辅助脚本：探测宿主机 IP 并写入 .env 的 HOST_IP

    集群总线端口 = 客户端端口 + 10000，必须一起对外开放，否则节点之间无法通信。
    主从对应关系由 redis-cli --cluster create 自动分配，以 cluster nodes 输出为准。
    以上端口(7001-7006、17001-17006)与仓库内其它服务(redis 6379、redis-sentinel 6379/6380/6381/26379-26381、kafka 9092 等)均不冲突。

# 密码

    123456

    # 每个节点都设置了 --requirepass 123456，从节点额外设置 --masterauth 123456 用于同步主节点数据
    # 需要改密码：修改 docker-compose.yml 中 6 个节点的 --requirepass/--masterauth，
    # 以及 redis-cluster-init 的 REDISCLI_AUTH
```

## 使用

### 1. 配置 HOST_IP（必做）

集群节点会用 `HOST_IP` 作为对外通告的地址，必须是**宿主机局域网 IP**（如 `192.168.1.4`），
不能是 `127.0.0.1`：6 个节点是独立容器，用 `127.0.0.1` 会导致节点互相连不上、客户端重定向(MOVED)失败。

直接用脚本探测并写入 `.env`（建议每次启动前跑一次）：

```bash
cd redis-cluster

./set-host-ip.sh                # 自动探测本机 IP 并写入 .env（WSL 下取 Windows 宿主机默认路由网卡 IP）
./set-host-ip.sh --print        # 只打印探测结果，不写入
./set-host-ip.sh 192.168.1.60   # 自动探测不准时，手动指定
```

脚本内置探测顺序：

```
WSL(Docker Desktop) 下 → 调用 powershell 取 Windows 默认路由网卡 IPv4
其它 Linux        → ip -4 route get 1.1.1.1 的 src，兜底 hostname -I
macOS             → ipconfig getifaddr en0
过滤掉 127.* / 169.254.* / 172.16-31.*(docker、WSL、Hyper-V 网段) / 192.168.122.*(libvirt)
```

执行后 `.env` 里的内容形如：

```bash
HOST_IP=192.168.1.4
```

IP 变化时脚本会提示重建集群（节点会把旧地址记录在 `nodes.conf` 里）：

```bash
docker compose down && sudo rm -rf /data/redis-cluster/* && docker compose up -d
```

### 2. 启动

```bash
cd redis-cluster

docker compose up -d

# 查看集群初始化日志（出现 >>> Performing hash slots allocation 即成功）
docker compose logs -f redis-cluster-init
```

初始化完成后 `redis-cluster-init` 容器会退出（`Exited (0)`），这是正常的。

### 3. 连接

```bash
# 集群模式连接（-c 表示自动跟随 MOVED/ASK 重定向）
redis-cli -c -h 127.0.0.1 -p 7001 -a 123456

# 查看集群状态
redis-cli -h 127.0.0.1 -p 7001 -a 123456 cluster info
redis-cli -h 127.0.0.1 -p 7001 -a 123456 cluster nodes
redis-cli -h 127.0.0.1 -p 7001 -a 123456 cluster slots

# 检查集群完整性（槽位、主从关系）
redis-cli --cluster check 127.0.0.1:7001 -a 123456

# 写入/读取测试（key 会按槽位路由到不同主节点）
redis-cli -c -h 127.0.0.1 -p 7001 -a 123456 set name freewu
redis-cli -c -h 127.0.0.1 -p 7001 -a 123456 get name
```

用 RedisInsight / 其它客户端连接时：连接任意一个节点端口（如 `127.0.0.1:7001`），密码 `123456`，
客户端勾选 **Cluster** 模式即可。

### 4. 重置集群

`nodes.conf` 和 AOF 数据都在 `/data/redis-cluster/node-*` 下，清空即可重新初始化：

```bash
cd redis-cluster
docker compose down
sudo rm -rf /data/redis-cluster/*      # Windows(Docker Desktop) 可用容器删：docker run --rm -v /data/redis-cluster:/d alpine sh -c 'find /d -mindepth 1 -delete'
docker compose up -d
```

## 常见问题

```
# 节点起不来 / 一直重启

    检查 .env 里的 HOST_IP 是否设置；启动命令通过 ${HOST_IP:?...} 做了必填校验，未设置会直接报错。

# 初始化容器日志报 "Waiting for the cluster to join" 卡住

    HOST_IP 填错了（比如填了 127.0.0.1），改成宿主机局域网 IP 后，
    docker compose down && sudo rm -rf /data/redis-cluster/* && docker compose up -d 重来。

# 宿主机能连但应用/其它容器连不上

    HOST_IP 必须是「容器之间也能访问」的地址；如果只需要容器网络内部访问（不需要宿主机客户端），
    可以把 docker-compose.yml 里的 --cluster-announce-ip/--cluster-announce-port/--cluster-announce-bus-port
    三行参数去掉，让节点使用容器自身 IP 通告。
```
