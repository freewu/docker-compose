# Consul 单节点服务端配置（参考 mysql/config/my.cnf 的写法，要调什么都在这里改）
#
# 默认端口（本文件不动就按这些端口启动，要改在这里加 ports { } 块）：
#   8300  server RPC（集群内部，节点之间用）
#   8301  serf LAN gossip（集群内部，TCP + UDP）
#   8302  serf WAN gossip（跨数据中心用，单机用不到）
#   8500  HTTP API + Web UI
#   8600  DNS 接口（TCP + UDP）
#   8501  HTTPS API，默认关闭（ports.https = -1）
#   8502  gRPC/xDS，2.x 默认关闭（ports.grpc = -1；1.x 里默认是 8502）
#   8503  gRPC-TLS，2.x 实测默认会监听（虽然文档说默认关闭），见文件末尾如何关掉

# 数据中心名（默认 dc1）
datacenter = "dc1"

# 节点名：固定成 consul。
# 不写的话默认用容器主机名（每次 docker 重建都会变），旧节点会以 failed 状态留在 catalog 里。
node_name = "consul"

# 单节点服务端：server = true + bootstrap_expect = 1，自己选举自己自动成为 leader
server = true
bootstrap_expect = 1

# 监听地址：容器里必须监听 0.0.0.0，否则宿主机连不上 8500（UI/API）和 8600（DNS）
# bind_addr 默认就是 0.0.0.0，这里显式写出来；client_addr 默认是 127.0.0.1，不改容器外就访问不到
bind_addr   = "0.0.0.0"
client_addr = "0.0.0.0"

# 对外通告的地址：显式取 eth0 的 IP（consul 支持 go-sockaddr 模板）。
# 不写的话 consul 会自动探测一个私网地址，一旦容器同时接入多个网络（多个私网 IP）就会直接启动失败：
#   "Multiple private IPv4 addresses found. Please configure one with 'bind' and/or 'advertise'"
# 如果容器的网卡名不是 eth0（极少见），改成对应网卡名，或注释掉这行让 consul 自动探测。
advertise_addr = "{{ GetInterfaceIP \"eth0\" }}"

# 数据目录（映射到宿主机 /data/consul/data：raft 日志、KV、服务目录、ACL 都在这里）
data_dir = "/consul/data"

# Web UI：http://localhost:8500/ui
# 注意：老写法 ui = true 在 2.x 里已废弃（会打 deprecation 警告），用下面这个
ui_config {
  enabled = true
}

# 日志级别：TRACE / DEBUG / INFO / WARN / ERROR，排查问题时可以临时改成 DEBUG
log_level = "INFO"

# 想省掉 8503（gRPC-TLS）监听 / 想改默认端口时，取消下面的注释：
# ports {
#   http     = 8500
#   dns      = 8600
#   grpc_tls = -1     # 2.x 默认会在 8503 上监听 gRPC-TLS，-1 = 关掉
# }

# 单机开发环境先不开的东西（生产必做，需要时在下面追加）：
#   1) ACL：
#        acl {
#          enabled        = true
#          default_policy = "deny"
#          tokens { initial_management = "<自定义的管理员 token>" }
#        }
#      开启后所有 API 请求都要带 X-Consul-Token 头（或 CONSUL_HTTP_TOKEN 环境变量）
#   2) gossip 加密：encrypt = "<16 字节 base64 密钥>"（consul keygen 生成）
#   3) TLS：verify_incoming / verify_outgoing / ca_file / cert_file / key_file
#
# 想扩成多节点集群时：
#   * bootstrap_expect 改成本集群 server 的数量（比如 3）
#   * 其它节点加 retry_join = ["<本机IP>:8300"]
#   * 需要把 8300 / 8301 / 8302 映射到宿主机（单机模式用不到，默认没映射）
