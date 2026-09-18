#!/bin/sh
# DolphinScheduler 管理员密码初始化（幂等）
#
# 由 docker-compose.yml 里的 ds-admin-init 服务执行。
# DolphinScheduler 的用户密码在库里存的是「不带盐的 MD5」（表 t_ds_user.user_password），
# 所以这里直接改库就行，不需要启动 DolphinScheduler（也不需要在 UI 里操作）。
#
# 注意：重复执行会把管理员密码改回 .env 里的值；如果你在 UI 里改过密码，
#       不要再执行本容器（除非你就是想改回来）。

set -u

log() { echo "[ds-admin-init] $*"; }
die() { log "错误：$*"; exit 1; }

DB_HOST=${DS_DB_HOST:?缺少环境变量 DS_DB_HOST}
DB_PORT=${DS_DB_PORT:?缺少环境变量 DS_DB_PORT}
DB_NAME=${DS_DB_NAME:?缺少环境变量 DS_DB_NAME}
DB_USER=${DS_DB_USER:?缺少环境变量 DS_DB_USER}
DB_PASSWORD=${DS_DB_PASSWORD:?缺少环境变量 DS_DB_PASSWORD}
ADMIN_USER=${DS_ADMIN_USER:?缺少环境变量 DS_ADMIN_USER}
ADMIN_PASSWORD=${DS_ADMIN_PASSWORD:?缺少环境变量 DS_ADMIN_PASSWORD}

# 用户名要拼进 SQL 的单引号里，做个守卫（密码只存 MD5，不受限制）
case "$ADMIN_USER" in
    *"'"*) die "DS_ADMIN_USER 不能包含单引号" ;;
esac

export PGPASSWORD="$DB_PASSWORD"

# $1=SQL：成功返回 0 并把结果放到 PSQL_OUT，失败返回 1 并把错误放到 PSQL_ERR
PSQL_OUT=""
PSQL_ERR=""
psql_run() {
    rc=0
    PSQL_OUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=1 -tA -c "$1" 2>/tmp/ds_admin_err.txt) || rc=$?
    PSQL_ERR=$(cat /tmp/ds_admin_err.txt 2>/dev/null)
    return "$rc"
}

MD5=$(printf '%s' "$ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)
case "$MD5" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
    *) die "计算密码 MD5 失败" ;;
esac

log "等待元数据库 ${DB_HOST}:${DB_PORT}/${DB_NAME} 就绪（表 t_ds_user）..."
COUNT=""
i=1
while [ "$i" -le 30 ]; do
    if psql_run "SELECT count(*) FROM t_ds_user WHERE user_name = '$ADMIN_USER'"; then
        COUNT=$(printf '%s' "$PSQL_OUT" | tr -d '[:space:]')
        case "$COUNT" in
            ''|*[!0-9]*) COUNT="" ;;
        esac
        [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ] && break
        [ $((i % 6)) -eq 1 ] && log "还没找到账号 ${ADMIN_USER}，继续等待 ds-schema-init 建表 ..."
    else
        # 每 6 次（30 秒）打一次日志，避免刷屏
        case "$PSQL_ERR" in
            *"does not exist"*)
                [ $((i % 6)) -eq 1 ] && log "元数据表还没建好，等待 ds-schema-init ..." ;;
            *)
                [ $((i % 6)) -eq 1 ] && log "连接元数据库失败：$PSQL_ERR" ;;
        esac
    fi
    i=$((i + 1))
    sleep 5
done

if [ -z "$COUNT" ] || [ "$COUNT" -le 0 ]; then
    die "等待元数据库超时，请先执行 docker compose logs ds-schema-init 看建表是否成功"
fi

log "设置管理员 ${ADMIN_USER} 的密码 ..."
psql_run "UPDATE t_ds_user SET user_password = '$MD5', update_time = now() WHERE user_name = '$ADMIN_USER'" \
    || die "更新密码失败：$PSQL_ERR"

psql_run "SELECT user_password FROM t_ds_user WHERE user_name = '$ADMIN_USER'" \
    || die "校验密码失败：$PSQL_ERR"
if [ "$(printf '%s' "$PSQL_OUT" | tr -d '[:space:]')" != "$MD5" ]; then
    die "校验失败，库里的密码不是 .env 中配置的值"
fi

log "设置成功"
log "登录地址：http://localhost:12345/dolphinscheduler/ui"
log "账号 ${ADMIN_USER} / 密码为 .env 中的 DS_ADMIN_PASSWORD"
