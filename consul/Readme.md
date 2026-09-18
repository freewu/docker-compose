## 说明
```
# 服务（单节点 server 模式，不是 -dev 临时模式，数据持久化）

    consul   Consul 服务端 + Web UI + DNS 接口，同时是 leader（bootstrap_expect = 1）

    * 只有 1 个容器，配置全部由 ./config/consul.hcl 提供，没有单独的初始化容器
    * 数据目录挂在宿主机 /data/consul/data（重启、升级镜像都不丢数据）
    * 默认不开 ACL（本机开发方便），需要时见下方"常见问题 4"

# 使用到的端口号

# 宿主机映射的端口（docker-compose.yml 里 publish 的 1:1 映射）

    | 端口 | 协议     | 用途                        | 访问示例                                            |
    |------|----------|-----------------------------|-----------------------------------------------------|
    | 8500 | TCP      | HTTP API + Web UI           | http://localhost:8500/ui                            |
    | 8600 | TCP+UDP  | DNS 接口（DNS 本身用 UDP）  | dig @127.0.0.1 -p 8600 consul.service.consul        |

# 只在容器内监听的端口（默认不映射到宿主机，所以不会和别的服务冲突）

    | 端口 | 协议     | 用途                        | 说明                                                |
    |------|----------|-----------------------------|-----------------------------------------------------|
    | 8300 | TCP      | server RPC（集群内部）       | 容器内监听，单机默认不映射；做集群时才需要映射      |
    | 8301 | TCP+UDP  | serf LAN gossip（集群内部）  | 同上                                                |
    | 8302 | TCP+UDP  | serf WAN gossip（跨机房）    | 同上                                                |
    | 8501 | TCP      | HTTPS API                    | 默认关闭（ports.https = -1），配了 TLS 才会监听     |
    | 8502 | TCP      | gRPC / xDS                   | 默认关闭（ports.grpc = -1）；1.x 默认监听 8502     |
    | 8503 | TCP      | gRPC-TLS                     | 2.x 实测默认会监听（容器内，未映射宿主机）；可关闭  |

    * 以上端口在整个仓库里没有和其它服务冲突（8500/8600 只有 Consul 用）；
      将来映射 8300/8301/8302 也不会冲突
    * 唯一要注意的是 8600 要同时映射 TCP 和 UDP 两条，少一条 dig 可能不通
    * 实测启动后监听情况：8500 ✓、8600(TCP+UDP) ✓、8300/8301/8302 ✓、8503 ✓；
      8501、8502 不监听；8503 想关掉就去 consul.hcl 里把 ports { grpc_tls = -1 } 的注释去掉

# 数据目录（宿主机绝对路径，删除即相当于重置 Consul）

    /data/consul/data    raft 日志、KV、服务目录（catalog）、ACL 等

# 镜像与版本

    hashicorp/consul:2.0.4   （官方镜像，alpine 基底，自带 curl，用 su-exec 降权到 consul 用户运行）
    想用 1.x 老版本：把 docker-compose.yml 里的 tag 换成 hashicorp/consul:1.22.7 即可，
    配置基本不用改（ui_config / advertise_addr 模板 / ports 块在 1.11+ 都支持）
```

## 启动与验证
```
# 启动

    docker compose up -d

# 看状态（healthy 表示已选主成功）

    docker compose ps
    docker compose logs -f consul

# HTTP API

    curl http://127.0.0.1:8500/v1/status/leader     # 返回 "172.x.x.x:8300" 表示已有 leader
    curl http://127.0.0.1:8500/v1/status/peers      # 集群成员
    curl http://127.0.0.1:8500/v1/catalog/nodes     # 节点目录

# 浏览器打开 Web UI（Services / Nodes / KV / ACL 等都在上面看）

    http://localhost:8500/ui

# KV 读写

    curl -X PUT -d 'hello consul' http://127.0.0.1:8500/v1/kv/demo/key
    curl http://127.0.0.1:8500/v1/kv/demo/key?raw            # hello consul
    curl 'http://127.0.0.1:8500/v1/kv/demo/?recurse'         # 列出该前缀下所有 key

# 注册一个服务（Address 换成你真实服务的地址，会被写进 DNS 解析结果）

    curl -X PUT -d '{"Name":"my-web","ID":"my-web-1","Address":"192.168.0.200","Port":8080}' \
      http://127.0.0.1:8500/v1/agent/service/register

    curl http://127.0.0.1:8500/v1/catalog/service/my-web

# DNS 解析（注册成功后即可解析，格式 <服务名>.service.<数据中心>.consul）

    dig @127.0.0.1 -p 8600 my-web.service.consul
    dig @127.0.0.1 -p 8600 consul.service.consul
    # Windows 没有 dig 时用 nslookup：
    nslookup -port=8600 my-web.service.consul 127.0.0.1

# 容器内用 consul 命令操作

    docker exec -it consul consul members
    docker exec -it consul consul catalog services
    docker exec -it consul consul kv put foo bar
    docker exec -it consul consul kv get foo

# 重新加载配置（改了 consul.hcl 后，大部分项支持热加载，不用重启容器）

    docker exec -it consul consul reload
    # 如果 reload 后不生效，多半是编辑器保存时“重命名替换”了文件，
    # 导致容器的 bind mount 还指向旧 inode：docker compose restart consul 即可

# 关停（数据保留在 /data/consul/data）

    docker compose down
```

## 配置说明（config/consul.hcl）
```
# 关键项

    datacenter      = "dc1"                数据中心名（DNS 里的 service.dc1.consul 用得到）
    node_name       = "consul"             固定节点名，避免容器重建后 catalog 里出现重复的旧节点
    server          = true                 服务端模式
    bootstrap_expect = 1                   单节点：自己选举自己
    bind_addr       = "0.0.0.0"            集群通信监听地址
    client_addr     = "0.0.0.0"            HTTP/DNS 监听地址，默认 127.0.0.1（不改容器外访问不到）
    data_dir        = "/consul/data"       对应宿主机 /data/consul/data
    ui_config { enabled = true }           打开 Web UI
    log_level       = "INFO"               排查问题可临时改 DEBUG

# 改端口：在 consul.hcl 里加 ports 块，同时改 docker-compose.yml 里 ports 左侧的数字

    ports {
      http = 8500
      dns  = 8600
    }

# 注意：镜像 entrypoint 会自动补 -data-dir / -config-dir，
#       compose 里的 command 只需要给子命令 agent，不要自己再写 -data-dir（重复设置容易混乱）
```

## 常见问题
```
# 1. UI 打不开 / curl 8500 拒绝连接

    docker compose logs -f consul     # 先看日志
    - 日志里如果写 "cluster leadership lost" / 一直在 election：数据目录里有旧集群的 raft 数据，
      清掉重建：docker compose down && rm -rf /data/consul/data/* && docker compose up -d
    - 8500 被占用：改 docker-compose.yml 里 ports 左侧数字（右侧 8500 是容器内端口，可不动）

# 2. 宿主机 dig 不通 8600

    - 确认两条映射都在：8600:8600/tcp 和 8600:8600/udp（DNS 走 UDP，少这条最常见）
    - 确认 consul.hcl 里 client_addr = "0.0.0.0"（默认 127.0.0.1 时容器外访问不到）
    - 直接用 +tcp 对比：dig +tcp @127.0.0.1 -p 8600 my-web.service.consul
    - 想让别的容器直接用 consul 做 DNS，可在那个服务上加：dns: [consul]（同网络内）

# 3. 容器重建后 catalog 里多出一个 failed 节点

    正常现象的原因：节点名默认取容器主机名，重建后主机名变了。
    本目录已固定 node_name = "consul" 规避；如果历史数据里已有旧节点：

        docker compose down
        rm -rf /data/consul/data/*
        docker compose up -d

# 4. 想开 ACL（生产建议）

    编辑 consul/config/consul.hcl 追加：

        acl {
          enabled        = true
          default_policy = "deny"
          tokens { initial_management = "改成你自己的长随机字符串" }
        }

    然后 docker compose up -d --force-recreate consul，之后所有请求都要带 token：

        curl -H "X-Consul-Token: <上面那个 token>" http://127.0.0.1:8500/v1/catalog/nodes
        # 或者登录 UI 时把 token 填进去；命令行用 export CONSUL_HTTP_TOKEN=<token>

    * 开 ACL 前写入的数据不会被删，但没 token 就查不到了，别慌
    * 注意 ACL 只能靠配置文件里的 initial_management token 或 consul acl bootstrap 初始化，
      不像 MySQL/Redis 那样"起个容器执行 SQL 设置账号密码"，所以本目录没有 .env、也没有 init 容器

# 5. 想扩成多节点集群

    1) consul.hcl：bootstrap_expect 改成 server 数量（比如 3），其它节点加
           retry_join = ["<本机IP>:8300"]
    2) docker-compose.yml：把 8300 / 8301 / 8302（TCP 和 UDP）也映射到宿主机
    3) 各节点 node_name 不能相同；生产还要配 encrypt（consul keygen 生成 gossip 密钥）
    4) 每个节点必须用各自独立的 /data/consul/data 目录（不能共用）

# 6. 彻底重置（连数据带容器）

    docker compose down
    rm -rf /data/consul/data/*
    docker compose up -d

# 7. 换 1.x（1.22.7）

    只改镜像 tag：image: hashicorp/consul:1.22.7，配置不用动。
    注意 1.x 默认会监听 8502（gRPC/xDS），而 2.x 默认关闭；要用 xDS 功能时两边写法不一样。

# 8. 启动报 "Multiple private IPv4 addresses found. Please configure one with 'bind' and/or 'advertise'"

    容器里存在多个私网 IP（比如同时接入多个 docker 网络），consul 自动探测 advertise 地址时无法选择。
    本目录已用 advertise_addr = "{{ GetInterfaceIP \"eth0\" }}" 固定取 eth0 防御这种情况：
    - 如果容器的网卡名不是 eth0，把这行改成真实网卡名（容器内 ip -o -4 addr list 查看）
    - 或者直接写容器固定 IP / 宿主机 IP：advertise_addr = "172.20.0.10"
    - 也可以反过来用 entrypoint 的 CONSUL_BIND_INTERFACE=eth0 环境变量（会补 -bind=eth0 的 IP）

    顺带说明：本目录的 consul.hcl 已经用真实 consul 2.0.4 二进制跑过 consul validate 验证语法，
    再跑一遍：docker exec -it consul consul validate /consul/config

# 9. consul.hcl 写错了怎么办

    配置有语法错误时容器会直接退出，日志里有行号和原因（docker compose logs consul）。
    想校验语法可以先跑一次性容器：

        docker run --rm -v "$PWD/config:/c:ro" hashicorp/consul:2.0.4 consul validate /c
```
