# RabbitMQ 服务
```
# 端口

    15672  # 提供的 web 服务器的接口
    5672

#  默认帐号 & 密码

    root / root

    # 如果需求 修改 docker-compose.yml 第 14，15 行即可
    environment:
      - RABBITMQ_DEFAULT_USER=root
      - RABBITMQ_DEFAULT_PASS=root

```