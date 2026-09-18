#!/bin/sh
#
# Nacos 控制台管理员密码初始化（幂等，可重复执行）
#
# 背景：Nacos 3.x 默认开启鉴权，第一个管理员账号的密码只能通过 API 写入（没有任何环境变量可以直接指定）。
#       官方控制台"初始化管理员账号"页面调用的就是 POST /v3/auth/user/admin
#       （见 console-ui-next/src/api/auth.ts，且该接口在免登录白名单里），
#       这里用同一个接口把密码设置成 .env 中配置的值，省得手动去页面点。
#
# 接口特性（Nacos 3.2.4 源码核验）：
#   * 只在"还没有全局管理员"时创建成功（HTTP 200），已存在时返回 409 + "have admin user cannot use it."
#   * 管理员用户名固定为 nacos（AuthConstants.DEFAULT_USER），接口无法指定其它用户名
#   * 密码上限 72 字符（BCrypt 限制）
#   * 密码以表单参数提交，curl --data-urlencode 会做 URL 编码，含特殊字符也安全
#
# 环境变量：
#   NACOS_ADMIN_PASSWORD  必填，控制台管理员密码
#   NACOS_SERVER_URL      可选，默认 http://nacos:8848/nacos（服务端 API 入口）
#   NACOS_CONSOLE_URL     可选，默认 http://nacos:8080（控制台入口，接口的备选入口）
#
# 退出码：0 = 成功（新建成功，或已存在且密码校验通过）；1 = 失败；2 = 用法/环境变量错误

set -u

log() {
    echo "[nacos-init] $*"
}

die() {
    log "错误：$*"
    exit 1
}

ADMIN_USER=nacos
ADMIN_PASSWORD=${NACOS_ADMIN_PASSWORD:-}
SERVER_URL=${NACOS_SERVER_URL:-http://nacos:8848/nacos}
CONSOLE_URL=${NACOS_CONSOLE_URL:-http://nacos:8080}

if [ -z "$ADMIN_PASSWORD" ]; then
    log "错误：缺少环境变量 NACOS_ADMIN_PASSWORD"
    exit 2
fi
if [ "${#ADMIN_PASSWORD}" -gt 72 ]; then
    log "错误：密码长度 ${#ADMIN_PASSWORD} 超过 Nacos 上限 72 字符"
    exit 2
fi

BODY_FILE=/tmp/nacos_init_body.txt
ERR_FILE=/tmp/nacos_init_err.txt

# 发送 POST 请求：参数为 curl 参数，输出 HTTP 状态码（失败时输出 000），响应体写入 $BODY_FILE
http_post() {
    code=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' -X POST "$@" 2>"$ERR_FILE") || true
    # 连接失败时 curl 本身也会输出 000，这里只兜底 curl 不可用/无输出的情况
    [ -n "$code" ] || code=000
    printf '%s' "$code"
}

# 是否已存在管理员（调用 /admin 接口时返回 409 或响应体带 have admin user 都算）
is_admin_exist() {
    printf '%s' "$1" | grep -q "have admin user"
}

# ---------------------------------------------------------------- 1. 等就绪 + 初始化管理员密码
RESULT=""
i=0
while [ "$i" -lt 60 ]; do
    i=$((i + 1))
    for base in "$SERVER_URL" "$CONSOLE_URL"; do
        code=$(http_post --data-urlencode "password=$ADMIN_PASSWORD" "$base/v3/auth/user/admin")
        body=$(cat "$BODY_FILE" 2>/dev/null || true)
        case "$code" in
            200)
                RESULT="created"
                log "管理员账号 $ADMIN_USER 已创建，密码取自 .env 中的 NACOS_ADMIN_PASSWORD"
                break 2
                ;;
            404)
                # 该入口没有这个接口（服务端/控制台端口不同），换下一个入口试
                continue
                ;;
            409)
                RESULT="exists"
                log "管理员账号 $ADMIN_USER 已存在，跳过创建（不做覆盖）"
                break 2
                ;;
            *)
                if is_admin_exist "$body"; then
                    RESULT="exists"
                    log "管理员账号 $ADMIN_USER 已存在，跳过创建（不做覆盖）"
                    break 2
                fi
                # 服务还没起来（000 连接失败 / 5xx 未就绪），继续等，每 6 次打一条日志避免刷屏
                if [ $((i % 6)) -eq 1 ]; then
                    log "等待 Nacos 就绪中（第 $i 次），入口 $base 返回 HTTP $code"
                fi
                ;;
        esac
    done
    sleep 5
done

if [ -z "$RESULT" ]; then
    log "最后一次响应：$(cat "$BODY_FILE" 2>/dev/null | head -c 300)"
    die "等待 Nacos 就绪超时（约 5 分钟）。请先看主容器日志：docker compose logs -f nacos"
fi

# ---------------------------------------------------------------- 2. 校验 .env 里的密码能登录
LOGIN_CODE=""
for base in "$SERVER_URL" "$CONSOLE_URL"; do
    LOGIN_CODE=$(http_post --data-urlencode "username=$ADMIN_USER" \
        --data-urlencode "password=$ADMIN_PASSWORD" "$base/v3/auth/user/login")
    if grep -q '"accessToken"' "$BODY_FILE" 2>/dev/null; then
        log "校验通过：.env 中的密码可以正常登录"
        log "控制台地址：http://localhost:8080/    账号：$ADMIN_USER（密码见 nacos/.env）"
        log "接口取 token：curl -X POST 'http://localhost:8848/nacos/v3/auth/user/login' -d 'username=$ADMIN_USER' -d 'password=<你的密码>'"
        exit 0
    fi
    [ "$LOGIN_CODE" = "404" ] && continue
done

log "最后一次登录响应（HTTP $LOGIN_CODE）：$(cat "$BODY_FILE" 2>/dev/null | head -c 300)"
die "用 .env 中的密码登录失败：说明控制台里的管理员密码不是这里配置的值。
     三种处理方式（任选其一）：
       1) 把 .env 的 NACOS_ADMIN_PASSWORD 改成控制台当前真实密码；
       2) 用已有密码登录控制台后在【用户管理】里改密码；
       3) 清空 /data/nacos/data（等于恢复出厂，数据会丢）后重建：docker compose down && rm -rf /data/nacos/data/* && docker compose up -d"
