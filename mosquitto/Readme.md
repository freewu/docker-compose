## 默认说明
```
# 默认帐号密码 默认使用 sha256 自己在 config/pwdfile 添加

    mqtt / mqtt1234

# 默认 topic ACL需要自己在 config/aclfile 里添加

    topic/#

```

## 启动服务
```
# 启动服务 

    docker-compose up -d

# 暂停服务 

    docker-compose stop

# 重启服务

    docker-compore restart

# 移除服务(需要先暂停服务)

    docker-compose rm
```

## 验证
```
# 获取到 container id 

    docker ps

# 进入容器内部

    docker exec -it <containerid> sh

# 开启订阅

    mosquitto_sub -h localhost -v -t "topic/#" -i "sub-1"  -u mqtt -P mqtt1234

    -c 指定客户端clean_session是否保存。
    -d 打印debug信息
    -h 指定要连接的域名 默认为localhost
    -i 指定客户端clientid
    -I 指定clientId前缀
    -k keepalive 每隔一段时间，发PING消息通知broker，仍处于连接状态。 默认为60秒.
    -q 指定希望接收到QoS为什么的消息 默认QoS为0
    -R 不显示陈旧的消息
    -t 订阅topic
    -v 打印消息
    --will-payload 指定一个消息，该消息当客户端与broker意外断开连接时发出。该参数需要与--will-topic一起使用
    --will-qos Will的QoS值。该参数需要与--will-topic一起使用
    --will-retain 指定Will消息被当做一个retain消息（即消息被广播后，该消息被保留起来）。该参数需要与--will-topic一起使>用
    --will-topic 用户发送Will消息的topic

# 发布信息( 需要再开一个终端 )

    mosquitto_pub -h localhost -t "topic/test" -i "pub-1" -m "Hello World" -u mqtt -P mqtt1234
```


## 认证配置文件
```
# 创建用户和密码

    mosquitto_passwd -b /mosquitto/config/pwdfile mqtt mqtt1234 # 然后输入及确认密码

# mosquitto_passwd 参数说明：

    -c 是创建一个新的文件，只保存一个用户
    -b 在文件中新增一个用户在最后
    -D 从文件中删除指定用户
    -H 密码加密方式 默认 sha256

```

## 权限配置文件 /mosquitto/config/aclfile
```
# 李雷只能发布以test为前缀的主题,订阅以$SYS开头的主题即系统主题
user lilei
topic write test/#
topic read $SYS/#

# 韩梅梅只能订阅以test为前缀的主题
user hanmeimei
topic read test/#
```