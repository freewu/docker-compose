#!/bin/sh
# 设置/重置 Doris root 密码（幂等，可重复执行）
#
# 由 docker compose 中的 doris-init 服务调用，账号密码来自 doris/.env：
#   DORIS_ROOT_USER      默认 root（Doris 内置管理员账号，一般不用改）
#   DORIS_ROOT_PASSWORD  必填，root 账号的登录密码
#
# 说明：Doris 的用户信息保存在 FE 元数据目录（/data/fe-01/doris-meta）中，
#       所以这个脚本只是把密码设置/重置成 .env 中配置的值，不会重复建用户。
set -u

FE_HOST="${FE_HOST:-172.20.80.2}"
FE_PORT="${FE_PORT:-9030}"
ROOT_USER="${DORIS_ROOT_USER:-root}"
ROOT_PASSWORD="${DORIS_ROOT_PASSWORD:-}"

log() { echo "[doris-init] $*"; }

if [ -z "$ROOT_PASSWORD" ]; then
    log "错误：未配置 DORIS_ROOT_PASSWORD，请在 doris/.env 中设置后重试"
    exit 1
fi

# 下面拼 SQL 时直接把密码包在单引号里，故不允许含单引号
case "$ROOT_PASSWORD$ROOT_USER" in
    *"'"*)
        log "错误：DORIS_ROOT_USER / DORIS_ROOT_PASSWORD 不能包含单引号 '"
        exit 1
        ;;
esac

# $1=密码（空表示无密码） $2=SQL
# 成功返回 0；失败返回 1，并把 mysql 的错误信息写入 MYSQL_ERR
MYSQL_ERR=""
mysql_run() {
    if [ -n "$1" ]; then
        MYSQL_ERR=$(mysql -h"$FE_HOST" -P"$FE_PORT" -u"$ROOT_USER" -p"$1" \
            --connect-timeout=5 --batch --skip-column-names -e "$2" 2>&1 >/dev/null)
    else
        MYSQL_ERR=$(mysql -h"$FE_HOST" -P"$FE_PORT" -u"$ROOT_USER" \
            --connect-timeout=5 --batch --skip-column-names -e "$2" 2>&1 >/dev/null)
    fi
    [ -z "$MYSQL_ERR" ]
}

log "等待 FE ${FE_HOST}:${FE_PORT} 就绪 ..."
ready=0
i=0
while [ "$i" -lt 60 ]; do
    i=$((i + 1))

    # 1) root 无密码可连 -> 待会儿设置密码
    if mysql_run "" "SELECT 1"; then
        ready=1
        break
    fi

    # 2) 客户端连接类错误（FE 还没起来）-> 继续等待
    case "$MYSQL_ERR" in
        *"Can't connect"*|*"Connection refused"*|*"Unknown MySQL server host"*|*"Lost connection"*|*"ERROR 20"*|*"timed out"*|*"Timed out"*)
            [ $((i % 6)) -eq 0 ] && log "已等待 $((i * 5)) 秒，FE 尚未就绪 ..."
            sleep 5
            continue
            ;;
    esac

    # 3) 其它错误一般是密码不对：先试 .env 里的密码
    if mysql_run "$ROOT_PASSWORD" "SELECT 1"; then
        log "root 密码已是 .env 中配置的密码，无需修改"
        exit 0
    fi
    log "错误：${ROOT_USER} 已有其它密码，与 .env 中的 DORIS_ROOT_PASSWORD 不一致"
    log "      处理：把 .env 中的 DORIS_ROOT_PASSWORD 改成现有密码，"
    log "            或删除 /data/fe-01/doris-meta、/data/fe-02/doris-meta、/data/fe-03/doris-meta 后重建集群"
    exit 1
done

if [ "$ready" != "1" ]; then
    log "等待 FE 超时（$((i * 5)) 秒）：$MYSQL_ERR"
    log "请先执行 docker compose logs -f docker-fe-01 检查 FE 是否正常启动"
    exit 1
fi

log "设置 ${ROOT_USER} 的密码 ..."
if mysql_run "" "SET PASSWORD FOR '${ROOT_USER}' = PASSWORD('${ROOT_PASSWORD}')"; then
    log "设置成功"
elif mysql_run "" "SET PASSWORD FOR '${ROOT_USER}'@'%' = PASSWORD('${ROOT_PASSWORD}')"; then
    log "设置成功（${ROOT_USER}@'%'）"
else
    log "设置失败：$MYSQL_ERR"
    exit 1
fi

if mysql_run "$ROOT_PASSWORD" "SELECT 1"; then
    log "校验通过：可用 ${ROOT_USER} / .env 中的密码登录（外部端口 9031/9032/9033）"
else
    log "校验失败：$MYSQL_ERR"
    exit 1
fi
log "完成"
