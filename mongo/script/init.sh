#!/usr/bin/env bash
#
# MongoDB 首次初始化脚本：挂到 /docker-entrypoint-initdb.d/，由镜像的 docker-entrypoint.sh 执行。
#
# 两个要点：
#   1. 只有当数据目录还是空的（第一次启动）才会执行，之后重启容器不会再跑，见 Readme「常见问题 6」
#   2. MongoDB 6.0 起镜像里已经没有老的 mongo shell，只有 mongosh，脚本里必须用 mongosh
#
# 这里建一个应用账号（管理员 root 由镜像按 .env 里的 MONGO_INITDB_ROOT_* 自动创建）。

set -e

ROOT_USER="${MONGO_INITDB_ROOT_USERNAME:-root}"
ROOT_PASSWORD="${MONGO_INITDB_ROOT_PASSWORD:-123456}"
APP_DB="${APP_DB:-hi}"
APP_USER="${APP_USER:-test}"
APP_PASSWORD="${APP_PASSWORD:-123456}"

echo "Creating mongo users ..."

mongosh --quiet "mongodb://${ROOT_USER}:${ROOT_PASSWORD}@127.0.0.1:27017/admin" --eval "
  const appDb = db.getSiblingDB('${APP_DB}');
  if (appDb.getUser('${APP_USER}')) {
    print('user ${APP_USER} already exists, skip');
  } else {
    appDb.createUser({
      user: '${APP_USER}',
      pwd: '${APP_PASSWORD}',
      roles: [{ role: 'readWrite', db: '${APP_DB}' }]
    });
    print('user ${APP_USER} -> db ${APP_DB} created');
  }
"

echo "Mongo users created."
