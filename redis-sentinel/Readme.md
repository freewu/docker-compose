# Redis 服务（哨兵模式）
```
# 端口

  服务           |   目录                |  占用端口         |  说明
--------------- |---------------------- | --------------- |-------
redis-master    | ./data/redis/master    | 6379            | 主节点
redis-slave1    | ./data/redis/slave1    | 6380            | 从节点1
redis-slave2    | ./data/redis/slave2    | 6381            | 从节点2
redis-sentinel1 |                       | 26379            | 哨兵节点1
redis-sentinel2 |                       | 26380            | 哨兵节点2
redis-sentinel3 |                       | 26381            | 哨兵节点3

# 密码

    123456

    # 三个 redis 节点都设置了 --requirepass 123456
    # 从节点额外设置 --masterauth 123456，用于同步主节点数据 / 主从切换后同步
    # 三个 sentinel 设置了 requirepass 123456（哨兵自身密码）
    #       以及 sentinel auth-pass mymaster 123456（哨兵连接主从节点用的密码）
    # 需要改密码时，docker-compose.yml 里这几处要一起改

# 主名称

    mymaster

# 启动前必须配置 HOST_IP

    docker-compose.yml 里 sentinel monitor 与 --replica-announce-ip 都用到了 ${HOST_IP}，
    必须设置为宿主机局域网 IP（不能用 127.0.0.1），否则哨兵无法监控、主从无法被客户端访问。

    Windows: ipconfig
    Linux:   hostname -I

    临时生效：export HOST_IP=192.168.1.60 && docker compose up -d

# 连接示例

    # 连接主节点
    redis-cli -h 127.0.0.1 -p 6379 -a 123456

    # 通过哨兵查询主节点地址（哨兵自身也要密码）
    redis-cli -h 127.0.0.1 -p 26379 -a 123456 sentinel get-master-addr-by-name mymaster

    # 查看主从信息
    redis-cli -h 127.0.0.1 -p 6379 -a 123456 info replication

```
