#!/bin/sh
# 设置 TiDB root 密码（幂等，可重复执行）
#
# 由 docker compose 中的 tidb-init 服务调用，账号密码来自 tidb/.env：
#   TIDB_ROOT_USER      默认 root（TiDB 内置管理员账号，一般不用改）
#   TIDB_ROOT_PASSWORD  必填，root 账号的登录密码（TiDB 默认空密码）
#
# 说明：TiDB 的账号信息存在 PD/TiKV 里（/data/tidb/tikv），所以这里只是把密码
#       设置/重置成 .env 中配置的值；集群刚起来时 TiKV/PD 可能还没就绪，脚本会重试。
set -u

TIDB_HOST="${TIDB_HOST:-tidb}"
TIDB_PORT="${TIDB_PORT:-4000}"
ROOT_USER="${TIDB_ROOT_USER:-root}"
ROOT_PASSWORD="${TIDB_ROOT_PASSWORD:-}"

log() { echo "[tidb-init] $*"; }

if [ -z "$ROOT_PASSWORD" ]; then
    log "错误：未配置 TIDB_ROOT_PASSWORD，请在 tidb/.env 中设置后重试"
    exit 1
fi

# 下面拼 SQL 时直接把密码包在单引号里，故不允许含单引号
case "$ROOT_PASSWORD$ROOT_USER" in
    *"'"*)
        log "错误：TIDB_ROOT_USER / TIDB_ROOT_PASSWORD 不能包含单引号 '"
        exit 1
        ;;
esac

SQL_ALTER="ALTER USER '${ROOT_USER}'@'%' IDENTIFIED BY '${ROOT_PASSWORD}'"
SQL_SET="SET PASSWORD FOR '${ROOT_USER}'@'%' = '${ROOT_PASSWORD}'"

# $1=密码（空表示无密码） $2=SQL
# 成功/失败看 mysql 的退出码（stderr 上可能还有 "Using a password ..." 之类的警告，不能当失败）；
# 失败时把错误信息写入 MYSQL_ERR，用于区分是连不上还是密码不对
MYSQL_ERR=""
mysql_run() {
    local rc
    if [ -n "$1" ]; then
        MYSQL_ERR=$(mysql -h"$TIDB_HOST" -P"$TIDB_PORT" -u"$ROOT_USER" -p"$1" \
            --connect-timeout=5 --batch --skip-column-names -e "$2" 2>&1 >/dev/null)
        rc=$?
    else
        MYSQL_ERR=$(mysql -h"$TIDB_HOST" -P"$TIDB_PORT" -u"$ROOT_USER" \
            --connect-timeout=5 --batch --skip-column-names -e "$2" 2>&1 >/dev/null)
        rc=$?
    fi
    [ "$rc" -eq 0 ]
}

log "等待 TiDB ${TIDB_HOST}:${TIDB_PORT} 就绪 ..."
ok=0
i=0
while [ "$i" -lt 60 ] && [ "$ok" != "1" ]; do
    i=$((i + 1))

    if mysql_run "" "SELECT 1"; then
        # root 无密码可连 -> 设置密码（集群刚起来时可能失败，继续重试）
        log "设置 ${ROOT_USER} 的密码 ..."
        if mysql_run "" "$SQL_ALTER" || mysql_run "" "$SQL_SET"; then
            log "设置成功"
            ok=1
        else
            log "设置失败（TiKV/PD 可能还没就绪），$((i * 5)) 秒后重试：$MYSQL_ERR"
        fi
    else
        case "$MYSQL_ERR" in
            # 客户端连接类错误：TiDB 还没起来，继续等待
            *"Can't connect"*|*"Connection refused"*|*"Unknown MySQL server host"*|*"Lost connection"*|*"ERROR 20"*|*"timed out"*|*"Timed out"*)
                [ $((i % 6)) -eq 0 ] && log "已等待 $((i * 5)) 秒，TiDB 尚未就绪 ..."
                ;;
            # 其它错误一般是密码已设置过：先试 .env 里的密码
            *)
                if mysql_run "$ROOT_PASSWORD" "SELECT 1"; then
                    log "root 密码已是 .env 中配置的密码，无需修改"
                    ok=1
                else
                    log "错误：${ROOT_USER} 已有其它密码，与 .env 中的 TIDB_ROOT_PASSWORD 不一致"
                    log "      处理：把 .env 中的 TIDB_ROOT_PASSWORD 改成现有密码，"
                    log "            或删除 /data/tidb 下所有数据后重建集群"
                    exit 1
                fi
                ;;
        esac
    fi

    [ "$ok" = "1" ] || sleep 5
done

if [ "$ok" != "1" ]; then
    log "等待 TiDB 超时（$((i * 5)) 秒）：$MYSQL_ERR"
    log "请先执行 docker compose logs -f tidb 检查 TiDB 是否正常启动"
    exit 1
fi

if mysql_run "$ROOT_PASSWORD" "SELECT 1"; then
    log "校验通过：可用 ${ROOT_USER} / .env 中的密码登录（外部端口 4000）"
else
    log "校验失败：$MYSQL_ERR"
    exit 1
fi
log "完成"
