## 说明
```
# 默认帐号密码（从 .env 读取，可外部修改）

    bluefrog / 12345678

# 端口

    9000 / 8123
```

## 账号密码外部配置（.env）
```
同目录下 .env 文件（容器启动时读取，改完需要重建容器才生效）：

    CLICKHOUSE_USER=bluefrog                              # 业务账号（只能字母/数字/下划线，不能以数字开头）
    CLICKHOUSE_PASSWORD=12345678                          # 业务账号密码（明文，建议只用字母数字，避免 xml 特殊字符）
    CLICKHOUSE_DB=                                        # 可选：启动时自动创建的数据库，留空不创建
    CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1                 # 1=该账号可管理用户/权限

# 生效方式

    docker compose up -d --force-recreate clickhouse

# 容器启动时由官方入口脚本把上面两个变量写入 users.d/default-user.xml（该文件已被 .gitignore 忽略）
# 同时删除镜像自带的 default 用户；config/users.xml 里只有 default 用户，且只允许本机访问

    docker exec -it clickhouse cat /etc/clickhouse-server/users.d/default-user.xml

# 修改账号或密码：编辑 .env 后重建容器即可，无需进入容器改配置

    vi .env
    docker compose up -d --force-recreate clickhouse
```

## 验证
```
# 心跳 clickhouse 暴露8123端口做健康检查

    curl http://127.0.0.1:8123/ping

# url 连接查询（账号密码来自 .env）

    curl "http://127.0.0.1:8123/?user=bluefrog&password=12345678&query=SELECT%20version()%20as%20version%20FORMAT%20JSON"

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

    clickhouse-client -h127.0.0.1 -ubluefrog --password 12345678

# 执行 SQL

    SHOW DATABASES;
```

## 常见问题
```
# 1. 只有 default 用户、.env 里的账号不生效

    说明当前镜像版本过老，入口脚本不支持 CLICKHOUSE_USER/CLICKHOUSE_PASSWORD 环境变量，
    建议把 docker-compose.yml 里的镜像换成官方维护版本：

        image: clickhouse/clickhouse-server:24.8

    （本仓库原用的 yandex/clickhouse-server 已停止更新）

# 2. 外部连接报 Authentication failed

    - 确认 .env 中的 CLICKHOUSE_PASSWORD 与客户端一致；
    - 确认改完 .env 后执行过 docker compose up -d --force-recreate clickhouse；
    - 用 default 账号从外部连接会失败（default 只允许本机/容器内访问，属正常）。

# 3. 需要额外固定账号（不走 .env）

    在 config/users.d/ 下新增 xml 文件（参考官方 users.xml 写法），例如 config/users.d/extra-user.xml：

        <clickhouse>
            <users>
                <extra>
                    <password_sha256_hex>密码的sha256</password_sha256_hex>
                    <networks><ip>::/0</ip></networks>
                    <profile>default</profile>
                    <quota>default</quota>
                </extra>
            </users>
        </clickhouse>

# 4. 生成密码 sha256

    PASSWORD=12345678; echo "$PASSWORD"; echo -n "$PASSWORD" | sha256sum | tr -d '-'
```
