# Redis 服务
```
# 端口

    6379

# 密码

    123456

    # 已开启密码：command: redis-server --requirepass 123456
    # 需要无密码访问时，把 docker-compose.yml 里的 command 改成 command: redis-server 即可

# 连接示例

    redis-cli -h 127.0.0.1 -p 6379 -a 123456
    redis-cli -h 127.0.0.1 -p 6379 -a 123456 ping

```
