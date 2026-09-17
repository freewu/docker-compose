#!/usr/bin/env bash
#
# 自动探测「宿主机局域网 IP」并写入 redis-cluster/.env 的 HOST_IP
#
# 用法:
#   ./set-host-ip.sh                # 自动探测并写入 .env
#   ./set-host-ip.sh 192.168.1.60   # 手动指定 IP 并写入 .env
#   ./set-host-ip.sh --print        # 只打印探测结果，不写入
#
# 探测顺序:
#   WSL(Docker Desktop) → Windows 默认路由网卡 IPv4 → 本机默认路由网卡 IPv4 → hostname -I
#   排除 127.* / 169.254.* / 172.16-31.*(docker、WSL、Hyper-V 默认网段) / 192.168.122.*(libvirt)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

info()  { printf '\033[32m%s\033[0m\n' "$*"; }
warn()  { printf '\033[33m%s\033[0m\n' "$*" >&2; }
error() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

usage() {
    cat <<'EOF'

自动探测「宿主机局域网 IP」并写入 redis-cluster/.env 的 HOST_IP

用法:
  ./set-host-ip.sh                # 自动探测并写入 .env
  ./set-host-ip.sh 192.168.1.60   # 手动指定 IP 并写入 .env
  ./set-host-ip.sh --print        # 只打印探测结果，不写入

探测顺序:
  WSL / Git Bash → 调用 powershell 取 Windows 默认路由网卡 IPv4
  其它 Linux     → ip -4 route get 1.1.1.1 的 src，兜底 hostname -I
  macOS         → ipconfig getifaddr en0
  过滤掉 127.* / 169.254.* / 172.16-31.*(docker、WSL、Hyper-V 网段) / 192.168.122.*(libvirt)
EOF
}

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
is_ipv4() { printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; }

# 是否是「合理的局域网 IP」候选：排除回环、链路本地、常见虚拟网卡网段
is_reasonable_ip() {
    is_ipv4 "$1" || return 1
    case "$1" in
        127.*|0.*|255.*)                       return 1 ;;
        169.254.*)                             return 1 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 1 ;;
        192.168.122.*)                         return 1 ;;
    esac
    return 0
}

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
    grep -qi microsoft /proc/version 2>/dev/null
}

# 是否在 Windows 侧（WSL / Git Bash / MSYS / Cygwin）
is_windows_shell() {
    is_wsl && return 0
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac
    return 1
}

# WSL / Git Bash 下向 Windows 侧查询「默认路由所在网卡」的 IPv4
# （NAT 模式 WSL 里本机 IP 是 172.x，必须取 Windows 宿主机的局域网 IP）
detect_windows_host_ip() {
    command -v powershell.exe >/dev/null 2>&1 || return 0
    powershell.exe -NoProfile -NonInteractive -Command '
        $r = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
             Where-Object { $_.NextHop -ne "0.0.0.0" } |
             Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
        if ($r) {
            (Get-NetIPAddress -InterfaceIndex $r.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Select-Object -First 1).IPAddress
        }
    ' 2>/dev/null | tr -d '\r\0' | grep -E '^[0-9]' || true
}

# Linux / WSL 本机默认路由网卡 IP
detect_linux_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null |
        awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true
    # 兜底：hostname -I（多网卡时全部列出来做候选）
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]' || true
}

# macOS
detect_macos_ip() {
    local i ip
    for i in en0 en1 en2 bridge0; do
        ip="$(ipconfig getifaddr "$i" 2>/dev/null || true)"
        [ -n "$ip" ] && printf '%s\n' "$ip"
    done
}

# 收集所有候选 IP（去重）
collect_candidates() {
    {
        is_windows_shell && detect_windows_host_ip
        case "$(uname -s)" in
            Darwin)              detect_macos_ip ;;
            MINGW*|MSYS*|CYGWIN*) : ;;
            *)                   detect_linux_ip ;;
        esac
    } | grep -E '^[0-9]' | awk '!seen[$0]++'
}

# 从候选中选出最合适的 IP
pick_ip() {
    local raw list ip
    raw="$(collect_candidates)"
    if [ -z "$raw" ]; then
        error "未能自动探测到本机 IP，请手动指定：$0 192.168.1.60"
        return 1
    fi
    list="$(printf '%s\n' "$raw" | while read -r ip; do is_reasonable_ip "$ip" && printf '%s\n' "$ip"; done)"
    if [ -z "$list" ]; then
        warn "探测到的地址看起来都是虚拟网卡网段，直接取第一个：$(printf '%s' "$raw" | head -1)"
        warn "如果不对，请手动指定：$0 你的局域网IP"
        list="$raw"
    fi
    printf '%s\n' "$list" | head -1
}

# ---------------------------------------------------------------------------
# 写入 .env
# ---------------------------------------------------------------------------
read_env_ip() {
    [ -f "$ENV_FILE" ] || return 0
    grep -E '^[[:space:]]*HOST_IP=' "$ENV_FILE" 2>/dev/null | head -1 |
        cut -d= -f2- | tr -d ' \t\r' || true
}

write_env_ip() {
    local ip="$1" tmp
    if [ ! -f "$ENV_FILE" ]; then
        {
            printf '# Redis Cluster 环境变量\n'
            printf '# HOST_IP：宿主机局域网 IP，由 set-host-ip.sh 写入\n'
            printf 'HOST_IP=%s\n' "$ip"
        } > "$ENV_FILE"
        return 0
    fi
    if grep -qE '^[[:space:]]*HOST_IP=' "$ENV_FILE"; then
        tmp="${ENV_FILE}.tmp.$$"
        sed -E "s|^[[:space:]]*HOST_IP=.*|HOST_IP=${ip}|" "$ENV_FILE" > "$tmp"
        mv "$tmp" "$ENV_FILE"
    else
        printf 'HOST_IP=%s\n' "$ip" >> "$ENV_FILE"
    fi
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
main() {
    local arg="${1:-}"

    case "$arg" in
        -h|--help) usage; exit 0 ;;
    esac

    local ip
    if [ -n "$arg" ] && [ "$arg" != "--print" ]; then
        is_ipv4 "$arg" || { error "参数不是合法的 IPv4 地址: $arg"; exit 1; }
        ip="$arg"
        info "使用手动指定的 IP: $ip"
    else
        ip="$(pick_ip)" || exit 1
        info "探测到本机 IP: $ip"
        is_reasonable_ip "$ip" || warn "注意：$ip 可能是虚拟网卡地址（容器/Docker Desktop 场景下应填宿主机局域网 IP）"
    fi

    if [ "$arg" = "--print" ]; then
        exit 0
    fi

    local old_ip
    old_ip="$(read_env_ip)"
    write_env_ip "$ip"
    info "已写入 ${ENV_FILE}: HOST_IP=${ip}"

    if [ -n "$old_ip" ] && [ "$old_ip" != "$ip" ]; then
        warn "HOST_IP 由 ${old_ip} 变为 ${ip}，集群里已记录的节点地址需要重建才干净，建议："
        warn "    cd ${SCRIPT_DIR} && docker compose down"
        warn "    sudo rm -rf /data/redis-cluster/*        # Windows(Docker Desktop) 用容器删"
        warn "    docker compose up -d"
    fi
}

main "$@"
