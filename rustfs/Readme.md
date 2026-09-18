# RustFS（单节点对象存储，S3 兼容）

[RustFS](https://rustfs.com) 是用 Rust 写的高性能分布式对象存储（Apache-2.0），接口兼容 S3，
可以当 MinIO 的替代品用（`aws-cli`、`mc`、各种 S3 SDK 都能连）。

本目录是**单机单卷**的最小可用部署：

- `rustfs`：RustFS 服务（S3 API + Web 控制台）
- `rustfs-perm`：一次性容器，把宿主机数据/日志目录属主改成镜像里的 `rustfs` 用户（uid/gid `10001`），执行完就退出

镜像：`rustfs/rustfs:1.0.0`（版本见同目录 `.env` 的 `RUSTFS_VERSION`）

> 本目录这套配置已经用官方 1.0.0 二进制 + 镜像里的 `entrypoint.sh` 实跑验证过：健康检查返回 `{"status":"ok",...}`、
> 建桶/上传/下载/删除对象（SigV4 签名）全部正常、重启容器后数据还在、compose 里的 healthcheck 命令退出码为 0。

## 端口

宿主机映射的端口（故意避开本仓库其它服务：9000 是 clickhouse、9001 是 portainer、9003/9004 是 minio）：

| 端口 | 容器内 | 用途 | 访问地址 |
| --- | --- | --- | --- |
| 9020 | 9000 | S3 API（aws-cli / SDK / mc 都连这个） | `http://localhost:9020` |
| 9021 | 9001 | Web 控制台（**注意路径前缀**） | `http://localhost:9021/rustfs/console/` |

容器内另外监听的端口（本目录不映射，也不会和宿主机其它服务冲突）：

| 端口 | 用途 | 对应环境变量 |
| --- | --- | --- |
| 9000 | S3 API | `RUSTFS_ADDRESS` |
| 9001 | Web 控制台 | `RUSTFS_CONSOLE_ADDRESS` |

健康检查端点（已在 1.0.0 实测）：

- S3 端口（9000）：`/health`、`/health/live`、`/health/ready` → `{"status":"ok","service":"rustfs-endpoint",...}`
- 控制台（9001）：`/rustfs/console/health`

> 除了上面两个端口，RustFS 单机模式不会监听别的端口（不像 MinIO 还要单独的 console 端口参数）。
> 将来做多节点集群时，节点之间走的是同一个 S3 端口 9000（`RUSTFS_VOLUMES` 里写 `http://节点:9000/...`）。

## 目录与数据

```
rustfs/
├── .env                 # 镜像版本、S3 账号密码、控制台开关、日志级别
├── docker-compose.yml
└── Readme.md
```

宿主机上的数据/日志：

- `/data/rustfs/data`：对象数据（删掉它等于清空所有 bucket）
- `/data/rustfs/logs`：`rustfs.log`（由 `RUSTFS_OBS_LOG_DIRECTORY=/logs` 决定）

## 启动与验证

```
# 启动（首次会自动创建 /data/rustfs/{data,logs} 并修正属主）

    docker compose up -d

# 看状态：rustfs 应该是 healthy；rustfs-perm 显示 Exited (0) 是正常的（一次性任务）

    docker compose ps
    docker compose logs -f rustfs

# 健康检查

    curl http://127.0.0.1:9020/health
    curl http://127.0.0.1:9020/health/ready
    curl http://127.0.0.1:9021/rustfs/console/health

# Web 控制台（用 .env 里的 RUSTFS_ACCESS_KEY / RUSTFS_SECRET_KEY 登录）

    http://localhost:9021/rustfs/console/

# 用 aws-cli 验证 S3 API（--endpoint-url 指向 9020）

    aws configure set default.s3.addressing_style path
    export AWS_ACCESS_KEY_ID=rustfs
    export AWS_SECRET_ACCESS_KEY=123456
    export AWS_DEFAULT_REGION=us-east-1

    aws --endpoint-url http://127.0.0.1:9020 s3 mb s3://demo            # 建桶
    aws --endpoint-url http://127.0.0.1:9020 s3 ls                     # 列桶
    echo hello > /tmp/hello.txt
    aws --endpoint-url http://127.0.0.1:9020 s3 cp /tmp/hello.txt s3://demo/hello.txt
    aws --endpoint-url http://127.0.0.1:9020 s3 ls s3://demo/          # 列对象
    aws --endpoint-url http://127.0.0.1:9020 s3 cp s3://demo/hello.txt -  # 读对象

# 用 mc（MinIO 客户端）也可以，别名指向 9020

    mc alias set rustfs http://127.0.0.1:9020 rustfs 123456
    mc ls rustfs

# 容器内的自检命令（rustfs 二进制自带 info / diagnose / inspect / tls 子命令）

    docker exec -it rustfs rustfs info
    docker exec -it rustfs rustfs diagnose /logs
    docker exec -it rustfs rustfs --version
```

## 配置说明（.env 与 docker-compose.yml）

常用参数都在 `.env` 里改，改完 `docker compose up -d` 生效（改 `.env` 会重建容器）：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `RUSTFS_VERSION` | `1.0.0` | 镜像 tag，留空则用 1.0.0 |
| `RUSTFS_ACCESS_KEY` | `rustfs` | S3 Access Key（**必填**，compose 做了非空校验；别名 `RUSTFS_ROOT_USER` / `MINIO_ROOT_USER` 也认） |
| `RUSTFS_SECRET_KEY` | `123456` | S3 Secret Key（**必填**；别名 `RUSTFS_ROOT_PASSWORD` / `MINIO_ROOT_PASSWORD` 也认） |
| `RUSTFS_CONSOLE_ENABLE` | `true` | 是否开启 Web 控制台，设 `false` 就只剩 S3 API |
| `RUSTFS_OBS_LOGGER_LEVEL` | `info` | 日志级别 `trace/debug/info/warn/error` |

`docker-compose.yml` 里已经写死的（一般不用动）：

- `RUSTFS_VOLUMES=/data`：数据落盘路径。**单卷**最简单，且不需要任何额外开关。
- `RUSTFS_ADDRESS=0.0.0.0:9000` / `RUSTFS_CONSOLE_ADDRESS=0.0.0.0:9001`：容器内监听地址，必须是 `0.0.0.0` 才能被宿主机访问；宿主机对外端口在 `ports` 里换（现在是 9020/9021）。
- `RUSTFS_OBS_LOG_DIRECTORY=/logs`：日志写文件（设成空字符串则只打 stdout）。

其它可能需要用到的环境变量（都不改也能跑）：

| 变量 | 说明 |
| --- | --- |
| `RUSTFS_SERVER_DOMAINS=s3.example.com` | 开启 virtual-hosted-style（`bucket.s3.example.com`）。AWS SDK / Terraform 等默认走 virtual-host 的客户端必填，否则要客户端侧强制 path-style |
| `RUSTFS_REGION` | 默认 `us-east-1`，客户端签名 region 要和它一致 |
| `RUSTFS_CONSOLE_PREFIX` | 控制台路径前缀，默认 `/rustfs/console` |
| `RUSTFS_TLS_PATH` | 证书目录，目录内放 `rustfs_cert.pem` + `rustfs_key.pem` 即开启 HTTPS（API + 控制台一起） |
| `RUSTFS_UNSAFE_BYPASS_DISK_CHECK=true` | 只给本地实验用：允许在同一块物理盘上挂多个数据卷 |
| `RUSTFS_ACCESS_KEY_FILE` / `RUSTFS_SECRET_KEY_FILE` | 从文件读凭证（配合 docker secrets），与直接给值互斥 |
| `RUSTFS_RPC_SECRET` | 多节点集群且用默认凭证时，节点间 RPC 认证用 |

想用多卷（同一块盘做实验）或真正多节点集群时，把 `RUSTFS_VOLUMES` 改成列表即可（容器内路径要落在挂载点上）：

```
# 4 个卷、单机一块盘：必须再开 RUSTFS_UNSAFE_BYPASS_DISK_CHECK=true，否则启动直接 FATAL
    RUSTFS_VOLUMES=/data/rustfs{0...3}
    RUSTFS_UNSAFE_BYPASS_DISK_CHECK=true

# 4 节点集群（每个节点 4 个卷），节点间走 9000 端口
    RUSTFS_VOLUMES=http://rustfs{1...4}:9000/data/rustfs{0...3}
```

> 卷数量（以及每组的盘数）一旦写进数据目录就不能原地改，改了会启动失败（见下面常见问题 4）。

## 常见问题

1. **控制台打不开 / 打开是 404 或 403**

   控制台不在根路径，要用 `http://localhost:9021/rustfs/console/`（最后带不带 `/` 都行）。
   直接访问 `http://localhost:9021/` 会返回 403（XML），因为 9001 上的非控制台路径会被当成 S3 请求处理，这是正常的。
   另外 `RUSTFS_CONSOLE_ENABLE=false` 时 9001 根本不监听，自然也打不开。

2. **容器起不来，日志里 `Local disk initialization failed ... Permission denied`**

   镜像里的进程是 `rustfs`（uid/gid `10001`），宿主机目录属主不对就写不进去。本目录已经用 `rustfs-perm`
   容器自动修正；如果你手动建过目录或换过目录，可以单独跑一次：

```
    docker compose up rustfs-perm
    # 或在容器里手动修（Windows Docker Desktop 只能这样）
    docker run --rm -v /data/rustfs/data:/data alpine chown -R 10001:10001 /data
```

3. **日志 `local erasure endpoints must use distinct physical disks`**

   一个卷组的多个卷落在同一块物理盘上，被安全校验拦住了（单盘机器挂 4 个卷就会这样）。
   本地做实验就把 `RUSTFS_UNSAFE_BYPASS_DISK_CHECK=true` 打开；生产请用真实的多块盘。

4. **改了卷数量后起不来：`pool topology mismatch ... cannot be changed in place`**

   数据目录里已经记了原来的卷结构，卷数量/每组的盘数不能原地改。要么把 `RUSTFS_VOLUMES` 改回原样，
   要么清空数据目录重来：

```
    docker compose down
    sudo rm -rf /data/rustfs/data/*        # Windows(Docker Desktop) 用容器删，见 Readme 底部
    docker compose up -d
```

5. **aws-cli / SDK 报 `InvalidAccessKeyId`、`SignatureDoesNotMatch`**

   - 确认用的就是 `.env` 里的 `RUSTFS_ACCESS_KEY` / `RUSTFS_SECRET_KEY`（改完 `.env` 要 `docker compose up -d` 重建容器才生效）。
   - `--endpoint-url` 用宿主机端口 `http://127.0.0.1:9020`（不是 9000）。
   - region 用 `us-east-1`（和 `RUSTFS_REGION` 一致）。
   - 自定义 endpoint 建议显式走 path-style：`aws configure set default.s3.addressing_style path`。

6. **AWS SDK / Terraform 报 `NoSuchBucket`（但桶明明存在）**

   这类客户端默认用 virtual-hosted-style（`bucket.域名`），需要告诉 RustFS 你的域名：
   `RUSTFS_SERVER_DOMAINS=s3.example.com`（多个域名用逗号分隔），并把域名解析指到本机。
   否则就让客户端强制 path-style。

7. **怎么换版本 / 换镜像**

   改 `.env` 里的 `RUSTFS_VERSION` 再 `docker compose up -d`。`latest` 目前指向 `1.0.0`；
   还有 `1.0.0-glibc`（glibc 变体，启动更快，镜像里额外带 `RUSTFS_ADDRESS`/`RUSTFS_CONSOLE_*` 等环境变量）。
   内网拉不动 Docker Hub 时，把 `image` 换成自己的镜像仓库地址即可。

8. **想开 HTTPS**

   把证书目录挂进容器（目录内文件名固定为 `rustfs_cert.pem` 和 `rustfs_key.pem`，想按域名多证书就再建子目录），
   然后设 `RUSTFS_TLS_PATH=/opt/tls`；同时把 healthcheck 里的 `http://` 改成 `https://` 并加 `-k`（或加 `--cacert`）。

9. **怎么彻底重置**

```
    docker compose down
    sudo rm -rf /data/rustfs/data/* /data/rustfs/logs/*
    docker compose up -d
```

10. **数据怎么备份/迁移**

    停掉容器后直接拷 `/data/rustfs/data`（保证一致性最简单）；不想停机就用 S3 接口搬：
    `mc mirror` 或 `aws s3 sync s3://demo s3://其它端点/demo`。

11. **日志在哪**

    `docker compose logs -f rustfs`（stdout）和 `/data/rustfs/logs/rustfs.log`（文件）都有。
    启动失败时文件日志通常比 stdout 更详细，也可以用 `docker exec -it rustfs rustfs diagnose /logs` 让它自己分析。

12. **Windows（Docker Desktop）上怎么删数据目录**

    没有 Linux 的 `sudo rm -rf`，用一次性容器删：

```
    docker run --rm -v /data/rustfs/data:/data alpine sh -c "rm -rf /data/*"
```
