## 说明
```
# 架构

    3 个 FE（docker-fe-01/02/03，容器名 doris-fe-01/02/03，IP 172.20.80.2/3/4）
    3 个 BE（docker-be-01/02/03，容器名 doris-be-01/02/03，IP 172.20.80.5/6/7）
    1 个初始化容器（doris-init，用于设置 root 密码，执行完自动退出）

# 默认帐号密码（从 .env 读取，可外部修改）

    root / 123456

# 端口

    FE  HTTP  8031、8032、8033
    FE  MySQL 9031、9032、9033
    BE  Web   8041、8042、8043

# 数据目录（宿主机绝对路径，删除即相当于重建集群）

    /data/fe-01/doris-meta  /data/fe-01/log
    /data/fe-02/doris-meta  /data/fe-02/log
    /data/fe-03/doris-meta  /data/fe-03/log
    /data/be-01/storage     /data/be-01/log
    /data/be-02/storage     /data/be-02/log
    /data/be-03/storage     /data/be-03/log
```

## 账号密码外部配置（.env）
```
同目录下 .env 文件：

    DORIS_ROOT_USER=root          # Doris 内置管理员账号就是 root，一般不用改
    DORIS_ROOT_PASSWORD=123456    # root 登录密码（Doris 默认空密码）

# 启动（首次启动会自动注册 FE/BE，FE 就绪约 30~60 秒，之后 doris-init 设置密码）

    docker compose up -d

# 查看设置密码的结果（doris-init 执行完退出属正常现象）

    docker compose logs -f doris-init
    # 正常输出示例：
    # [doris-init] 等待 FE 172.20.80.2:9030 就绪 ...
    # [doris-init] 设置 root 的密码 ...
    # [doris-init] 设置成功
    # [doris-init] 校验通过：可用 root / .env 中的密码登录（外部端口 9031/9032/9033）

# 修改密码：编辑 .env 后重建 doris-init 即可

    vi .env
    docker compose up -d --force-recreate doris-init
    docker compose logs -f doris-init

# 注意：Doris 的账号信息存在 FE 元数据里，不随 .env 自动变化。
#       如果手动改过 root 密码，请把 .env 中的 DORIS_ROOT_PASSWORD 改成同一个值，
#       否则 doris-init 会提示"已有其它密码"（不会覆盖，避免误改）。
```

## 连接
```
# 使用 mysql 客户端连接（宿主机上）

    mysql -h127.0.0.1 -P9031 -uroot -p123456

# 或在容器里连

    docker exec -it doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -p123456

# 常用校验

    SHOW FRONTENDS;
    SHOW BACKENDS;
    SHOW DATABASES;
    SELECT VERSION();
```

## 新建业务账号
```
# Doris 2.0 需要带上主机名（2.1+ 可以省略 @'%'）

    CREATE USER 'bluefrog'@'%' IDENTIFIED BY '12345678';
    GRANT ALL ON *.*.* TO 'bluefrog'@'%';

# 查看用户

    SHOW GRANTS;
```

## 常见问题
```
# 1. doris-init 提示"已有其它密码"

    root 现有密码与 .env 中的 DORIS_ROOT_PASSWORD 不一致，把 .env 改成现有密码即可；
    若确实忘了密码，删除 /data/fe-01/doris-meta（三个 FE 的都要删）后重建集群：

        docker compose down
        rm -rf /data/fe-0*/doris-meta
        docker compose up -d

# 2. doris-init 提示"等待 FE 超时"

    FE 启动失败，先看日志：docker compose logs -f docker-fe-01
    常见原因是 FE_SERVERS / 172.20.80.0/24 网段与已有网络冲突。

# 3. 端口说明

    9030 是 FE 容器内 MySQL 端口，9031/9032/9033 是映射到宿主机的端口；
    修改 root 密码必须连主 FE（FE_ID=1，即 172.20.80.2 / docker-fe-01 / 9031）。
```
