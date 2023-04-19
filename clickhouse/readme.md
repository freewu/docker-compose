## 说明
```
# 默认帐号密码

    bluefrog / 12345678

# 端口

    9000 / 8123
    
```

## 生成密码
```
# 进入容器

    docker exec -it clickhouse /bin/bash

# 随机8位密码

    PASSWORD=$(base64 < /dev/urandom | head -c8); echo "$PASSWORD"; echo -n "$PASSWORD" | sha256sum | tr -d '-'

# 指定密码

    PASSWORD=12345678; echo "$PASSWORD"; echo -n "$PASSWORD" | sha256sum | tr -d '-'

```

## 验证
```
# 心跳 clickhouse 暴露8123端口做健康检查
    
    curl http://192.168.5.132:8123/ping

# url 连接查询

    curl http://192.168.5.132:8123/?user=bluefrog&password=12345678&query=SELECT%20version()%20as%20version%20FORMAT%20JSON

# 使用 tabix 连接

    git clone https://github.com/tabixio/tabix.git
    cd tabix
    yarn install
    yarn start
```

## 使用 clickhouse 客户端连接
```
# 进入容器

    docker exec -it clickhouse /bin/bash

# 客户端连接

    clickhouse-client -h127.0.0.1 -ubluefrog -password12345678

# 执行 SQL

    SHOW DATABASES;

```