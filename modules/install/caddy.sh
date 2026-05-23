#!/bin/bash
# modules/install/caddy.sh
# Caddy 安装与通用 HTTPS 入口管理模块
#
# 功能:
# - 从 Caddy 官方下载接口安装最新版静态二进制
# - 创建 systemd 服务,由非 root 的 caddy 用户运行
# - 生成适配 Cloudflare 橙云的 Caddyfile,通过 HTTP-01 自动签发源站证书
# - 通过 apps.d 片段管理 s-ui、Nezha 和自定义应用反代

# ============ 模块元数据 ============
MODULE_NAME="Caddy"
MODULE_VERSION="1.1.0"
MODULE_DEPS=""
MODULE_CATEGORY="install"
MODULE_DESC="安装 Caddy 并管理应用 HTTPS 入口"

# ============ 全局变量 ============
CADDY_BIN="/usr/local/bin/caddy"
CADDY_DIR="/etc/caddy"
CADDYFILE="$CADDY_DIR/Caddyfile"
CADDY_APPS_DIR="$CADDY_DIR/apps.d"
CADDY_SERVICE="/etc/systemd/system/caddy.service"
CADDY_DATA_DIR="/var/lib/caddy"
CADDY_LOG_DIR="/var/log/caddy"
INSTALL_FLAG="/var/log/vps-tools/install-caddy.flag"
APPS_STATE_DIR="/var/log/vps-tools/caddy-apps"
CADDY_DOWNLOAD_BASE="https://caddyserver.com/api/download"

DEFAULT_DASHBOARD_PORT="2095"
DEFAULT_SUBSCRIPTION_PORT="2096"
DEFAULT_SUBSCRIPTION_PATH="/sub"
DEFAULT_NEZHA_PORT="8008"

CADDY_DOMAIN=""
CADDY_EMAIL=""
CADDY_DASHBOARD_PORT="$DEFAULT_DASHBOARD_PORT"
CADDY_SUBSCRIPTION_PORT="$DEFAULT_SUBSCRIPTION_PORT"
CADDY_SUBSCRIPTION_PATH="$DEFAULT_SUBSCRIPTION_PATH"
CADDY_NEZHA_PORT="$DEFAULT_NEZHA_PORT"
CADDY_CUSTOM_UPSTREAM=""
CADDY_SELECTED_APP_NAME=""
CADDY_ENABLE_BASIC_AUTH="false"
CADDY_AUTH_USER=""
CADDY_AUTH_PASSWORD=""
CADDY_AUTH_HASH=""

# ============ 检查函数 ============
check_installed() {
    command -v caddy &>/dev/null || [ -f "$INSTALL_FLAG" ]
}

check_dependencies() {
    return 0
}

check_sui_installed() {
    command -v s-ui &>/dev/null || [ -f /var/log/vps-tools/install-s-ui.flag ] || [ -f /usr/local/s-ui/installed.flag ]
}

check_nezha_installed() {
    [ -f /var/log/vps-tools/install-nezha.flag ] || \
    [ -f /opt/nezha/dashboard/docker-compose.yaml ] || \
    [ -f /opt/nezha/dashboard/app ] || \
    systemctl list-unit-files 2>/dev/null | grep -q "^nezha-dashboard.service"
}

pause_caddy_menu() {
    echo
    read -r -p "按 Enter 继续..."
}

# ============ 校验与输入 ============
is_private_ipv4() {
    local ip="$1"
    local first second third fourth

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi

    IFS='.' read -r first second third fourth <<< "$ip"
    first=$((10#$first))
    second=$((10#$second))
    third=$((10#$third))
    fourth=$((10#$fourth))

    if [ "$first" -gt 255 ] || [ "$second" -gt 255 ] || [ "$third" -gt 255 ] || [ "$fourth" -gt 255 ]; then
        return 1
    fi

    # RFC1918、回环、链路本地、CGNAT、文档示例和多播网段都不能作为公网 DNS 校验依据
    if [ "$first" -eq 0 ] ||
       [ "$first" -eq 10 ] ||
       [ "$first" -eq 127 ] ||
       [ "$first" -ge 224 ] ||
       { [ "$first" -eq 169 ] && [ "$second" -eq 254 ]; } ||
       { [ "$first" -eq 172 ] && [ "$second" -ge 16 ] && [ "$second" -le 31 ]; } ||
       { [ "$first" -eq 192 ] && [ "$second" -eq 168 ]; } ||
       { [ "$first" -eq 100 ] && [ "$second" -ge 64 ] && [ "$second" -le 127 ]; } ||
       { [ "$first" -eq 192 ] && [ "$second" -eq 0 ] && [ "$third" -eq 2 ]; } ||
       { [ "$first" -eq 198 ] && { [ "$second" -eq 18 ] || [ "$second" -eq 19 ]; }; } ||
       { [ "$first" -eq 198 ] && [ "$second" -eq 51 ] && [ "$third" -eq 100 ]; } ||
       { [ "$first" -eq 203 ] && [ "$second" -eq 0 ] && [ "$third" -eq 113 ]; }; then
        return 0
    fi

    return 1
}

get_public_server_ip() {
    local ip
    local endpoints=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://ipinfo.io/ip"
    )
    local endpoint

    for endpoint in "${endpoints[@]}"; do
        ip="$(curl -fsS --max-time 5 "$endpoint" 2>/dev/null | tr -d '[:space:]')"
        if validate_ip "$ip" >/dev/null 2>&1 && ! is_private_ipv4 "$ip"; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

get_caddy_arch() {
    local machine
    machine="$(uname -m)"

    case "$machine" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        armv6l) echo "armv6" ;;
        armv5*|armv5l) echo "armv5" ;;
        *)
            log_error "暂不支持的系统架构: $machine"
            return 1
            ;;
    esac
}

is_valid_public_domain() {
    local domain="$1"
    local label
    local -a labels

    if [ -z "$domain" ] || [ "$domain" = "localhost" ]; then
        return 1
    fi

    if [[ "$domain" == \*.* ]]; then
        log_error "当前模块不支持通配符域名,请使用明确的子域名"
        return 1
    fi

    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi

    if [[ "$domain" != *.* ]] || [[ "$domain" == .* ]] || [[ "$domain" == *. ]]; then
        return 1
    fi

    IFS='.' read -ra labels <<< "$domain"
    for label in "${labels[@]}"; do
        if [ -z "$label" ] || [ "${#label}" -gt 63 ]; then
            return 1
        fi
        if ! [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
            return 1
        fi
    done

    local last_label="${labels[${#labels[@]}-1]}"
    [[ "$last_label" =~ ^[a-z]{2,}$ ]]
}

resolve_domain_ipv4() {
    local domain="$1"

    if command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' '
        return 0
    fi

    return 1
}

normalize_path_prefix() {
    local path="$1"

    if [ -z "$path" ]; then
        path="$DEFAULT_SUBSCRIPTION_PATH"
    fi

    if [[ "$path" != /* ]]; then
        path="/$path"
    fi

    while [ "${#path}" -gt 1 ] && [[ "$path" == */ ]]; do
        path="${path%/}"
    done

    echo "$path"
}

is_valid_path_prefix() {
    local path="$1"

    [[ "$path" =~ ^/[A-Za-z0-9._~/-]+$ ]] && [ "$path" != "/" ]
}

is_valid_app_name() {
    local name="$1"
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]
}

normalize_app_name() {
    local name="$1"
    name="$(printf "%s" "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')"
    while [[ "$name" == -* ]]; do
        name="${name#-}"
    done
    while [[ "$name" == *- ]]; do
        name="${name%-}"
    done
    echo "${name:-app}"
}

default_app_name_from_domain() {
    local domain="$1"
    local first_label="${domain%%.*}"
    normalize_app_name "$first_label"
}

resolve_existing_email() {
    if [ -f "$INSTALL_FLAG" ]; then
        grep "^Email:" "$INSTALL_FLAG" 2>/dev/null | cut -d: -f2- | sed 's/^ *//'
    fi
}

show_domain_notice() {
    local ip
    ip="$(get_public_server_ip 2>/dev/null || true)"

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Caddy HTTPS 访问配置${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}Cloudflare 橙云模式准备事项:${NC}
  1. 在 Cloudflare DNS 创建 A 记录,内容填当前服务器${BOLD}公网 IPv4${NC}: ${GREEN}${ip:-请从云厂商控制台确认}${NC}
  2. 将该记录设置为 ${YELLOW}Proxied / 橙云${NC}
  3. Cloudflare SSL/TLS 模式建议设为 ${GREEN}Full (strict)${NC}
  4. 云厂商安全组/防火墙放行 ${GREEN}80/tcp${NC} 和 ${GREEN}443/tcp${NC}

${YELLOW}${BOLD}提示:${NC}
  80 仅用于 ACME HTTP-01 证书验证和 HTTP 到 HTTPS 跳转。
  日常访问仍使用 https:// 域名,不要直接暴露 s-ui 的 2095/2096。

EOF
}

confirm_cloudflare_dns_ready() {
    local domain="$1"
    local resolved_ips

    resolved_ips="$(resolve_domain_ipv4 "$domain")"

    if [ -n "$resolved_ips" ]; then
        log_info "$domain 当前公开解析到: $resolved_ips"
        log_info "如果已开橙云,这里显示 Cloudflare 边缘 IP 是正常现象"
    else
        log_warning "未查询到 $domain 的 IPv4 解析记录"
    fi

    ask_yes_no "是否已确认 Cloudflare A 记录内容为 VPS 公网 IP 且橙云已开启?" "y"
}

prompt_cloudflare_domain() {
    local prompt="$1"
    local domain
    while true; do
        printf "${BLUE}%s: ${NC}" "$prompt"
        read -r domain
        domain="$(echo "$domain" | tr '[:upper:]' '[:lower:]')"

        if is_valid_public_domain "$domain"; then
            if confirm_cloudflare_dns_ready "$domain"; then
                CADDY_DOMAIN="$domain"
                return 0
            fi
            return 1
        fi

        log_error "域名无效,示例: panel.example.com"
    done
}

collect_global_email() {
    local email
    local current_email

    current_email="$(resolve_existing_email)"
    if [ -n "$current_email" ]; then
        printf "${BLUE}请输入 ACME 通知邮箱 [默认%s, 可留空]: ${NC}" "$current_email"
    else
        printf "${BLUE}请输入 ACME 通知邮箱 (可留空): ${NC}"
    fi
    read -r email
    email=${email:-$current_email}

    if [ -n "$email" ]; then
        if validate_email "$email"; then
            CADDY_EMAIL="$email"
        else
            log_warning "邮箱格式无效,将不写入 ACME 邮箱"
            CADDY_EMAIL=""
        fi
    else
        CADDY_EMAIL=""
    fi
}

prompt_app_name() {
    local default_name="$1"
    local app_name

    while true; do
        printf "${BLUE}应用标识 [默认%s]: ${NC}" "$default_name"
        read -r app_name
        app_name=${app_name:-$default_name}
        app_name="$(normalize_app_name "$app_name")"

        if is_valid_app_name "$app_name"; then
            CADDY_SELECTED_APP_NAME="$app_name"
            return 0
        fi

        log_error "应用标识无效,只能使用小写字母、数字、下划线、短横线,最多32个字符"
    done
}

collect_sui_proxy_config() {
    local port
    local path

    show_domain_notice

    prompt_cloudflare_domain "请输入用于访问 s-ui 的域名" || return 1

    while true; do
        printf "${BLUE}s-ui dashboard 本地端口 [默认${DEFAULT_DASHBOARD_PORT}]: ${NC}"
        read -r port
        port=${port:-$DEFAULT_DASHBOARD_PORT}

        if validate_port "$port"; then
            CADDY_DASHBOARD_PORT="$port"
            break
        fi
    done

    while true; do
        printf "${BLUE}s-ui 订阅本地端口 [默认${DEFAULT_SUBSCRIPTION_PORT}]: ${NC}"
        read -r port
        port=${port:-$DEFAULT_SUBSCRIPTION_PORT}

        if validate_port "$port"; then
            CADDY_SUBSCRIPTION_PORT="$port"
            break
        fi
    done

    while true; do
        printf "${BLUE}订阅公网路径 [默认${DEFAULT_SUBSCRIPTION_PATH}]: ${NC}"
        read -r path
        path="$(normalize_path_prefix "$path")"

        if is_valid_path_prefix "$path"; then
            CADDY_SUBSCRIPTION_PATH="$path"
            break
        fi

        log_error "路径无效,示例: /sub"
    done

    if ask_yes_no "是否为 dashboard 额外启用 Basic Auth? (默认不启用)" "n"; then
        CADDY_ENABLE_BASIC_AUTH="true"
        collect_basic_auth_config || return 1
    fi

    return 0
}

collect_nezha_proxy_config() {
    local port

    show_domain_notice
    prompt_cloudflare_domain "请输入用于访问 Nezha Dashboard 的域名" || return 1

    while true; do
        printf "${BLUE}Nezha Dashboard 本地端口 [默认${DEFAULT_NEZHA_PORT}]: ${NC}"
        read -r port
        port=${port:-$DEFAULT_NEZHA_PORT}

        if validate_port "$port"; then
            CADDY_NEZHA_PORT="$port"
            break
        fi
    done

    cat << EOF

${YELLOW}${BOLD}Nezha 提示:${NC}
  Nezha V1 Dashboard 和 Agent 通信默认共享 8008 端口。
  Cloudflare 橙云需要 WebSocket 支持;Agent 通信建议按 Nezha 文档检查。

EOF

    return 0
}

collect_custom_proxy_config() {
    local port
    local upstream_host

    show_domain_notice
    prompt_cloudflare_domain "请输入用于访问应用的域名" || return 1

    printf "${BLUE}上游主机 [默认127.0.0.1]: ${NC}"
    read -r upstream_host
    upstream_host=${upstream_host:-127.0.0.1}

    while true; do
        printf "${BLUE}上游端口: ${NC}"
        read -r port

        if validate_port "$port"; then
            CADDY_CUSTOM_UPSTREAM="$upstream_host:$port"
            break
        fi
    done

    return 0
}

collect_basic_auth_config() {
    local password
    local password_confirm

    while true; do
        printf "${BLUE}Basic Auth 用户名 [默认admin]: ${NC}"
        read -r CADDY_AUTH_USER
        CADDY_AUTH_USER=${CADDY_AUTH_USER:-admin}

        if validate_username "$CADDY_AUTH_USER"; then
            break
        fi
    done

    while true; do
        printf "${BLUE}Basic Auth 密码: ${NC}"
        read -r -s password
        echo
        printf "${BLUE}再次输入 Basic Auth 密码: ${NC}"
        read -r -s password_confirm
        echo

        if [ -z "$password" ]; then
            log_error "密码不能为空"
            continue
        fi

        if [ "$password" != "$password_confirm" ]; then
            log_error "两次密码不一致"
            continue
        fi

        CADDY_AUTH_PASSWORD="$password"
        return 0
    done
}

# ============ 安装与配置 ============
install_caddy_binary() {
    local arch
    local tmp_dir
    local tmp_bin
    local download_url
    local version

    arch="$(get_caddy_arch)" || return 1
    tmp_dir="$(mktemp -d)"
    tmp_bin="$tmp_dir/caddy"
    download_url="${CADDY_DOWNLOAD_BASE}?os=linux&arch=${arch}"

    log_info "从 Caddy 官方下载接口安装最新版: $download_url"

    if ! curl -fL --connect-timeout 15 --retry 3 -o "$tmp_bin" "$download_url"; then
        log_error "下载 Caddy 失败"
        rm -rf "$tmp_dir"
        return 1
    fi

    chmod +x "$tmp_bin"

    if ! "$tmp_bin" version >/dev/null 2>&1; then
        log_error "下载的 Caddy 二进制校验失败"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! command install -m 0755 "$tmp_bin" "$CADDY_BIN"; then
        log_error "安装 Caddy 二进制失败"
        rm -rf "$tmp_dir"
        return 1
    fi

    version="$("$CADDY_BIN" version 2>/dev/null | awk '{print $1}')"
    rm -rf "$tmp_dir"

    log_success "Caddy 已安装: ${version:-unknown}"
    return 0
}

ensure_caddy_user_and_dirs() {
    if ! getent group caddy >/dev/null 2>&1; then
        groupadd --system caddy
    fi

    if ! id caddy >/dev/null 2>&1; then
        useradd --system \
            --gid caddy \
            --create-home \
            --home-dir "$CADDY_DATA_DIR" \
            --shell /usr/sbin/nologin \
            caddy
    fi

    mkdir -p "$CADDY_DIR" "$CADDY_APPS_DIR" "$CADDY_DATA_DIR" "$CADDY_LOG_DIR" "$APPS_STATE_DIR"
    chown root:caddy "$CADDY_DIR"
    chmod 755 "$CADDY_DIR"
    chown -R root:caddy "$CADDY_APPS_DIR"
    chmod 755 "$CADDY_APPS_DIR"
    chown -R caddy:caddy "$CADDY_DATA_DIR" "$CADDY_LOG_DIR"
    chmod 755 "$APPS_STATE_DIR"

    return 0
}

write_systemd_service() {
    if [ -f "$CADDY_SERVICE" ]; then
        backup_file "$CADDY_SERVICE" >/dev/null || return 1
    fi

    cat > "$CADDY_SERVICE" <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=$CADDY_BIN run --environ --config $CADDYFILE
ExecReload=$CADDY_BIN reload --config $CADDYFILE --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
Restart=on-failure
RestartPreventExitStatus=1
ReadWritePaths=$CADDY_DATA_DIR $CADDY_LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

    return 0
}

hash_basic_auth_password() {
    if [ "$CADDY_ENABLE_BASIC_AUTH" != "true" ]; then
        return 0
    fi

    CADDY_AUTH_HASH="$(printf "%s" "$CADDY_AUTH_PASSWORD" | "$CADDY_BIN" hash-password --algorithm argon2id 2>/dev/null)"
    CADDY_AUTH_PASSWORD=""

    if [ -z "$CADDY_AUTH_HASH" ]; then
        log_error "生成 Basic Auth 密码哈希失败"
        return 1
    fi

    return 0
}

ensure_caddy_layout() {
    mkdir -p "$CADDY_APPS_DIR" "$APPS_STATE_DIR"
    if [ ! -f "$CADDY_APPS_DIR/_placeholder.caddy" ]; then
        cat > "$CADDY_APPS_DIR/_placeholder.caddy" <<'EOF'
# Placeholder so Caddy import works before applications are added.
EOF
    fi
    chown -R root:caddy "$CADDY_DIR" 2>/dev/null || true
    chmod 755 "$CADDY_DIR" "$CADDY_APPS_DIR"
}

write_main_caddyfile() {
    local email_line=""

    if [ -n "$CADDY_EMAIL" ]; then
        email_line="    email $CADDY_EMAIL"
    fi

    if [ -f "$CADDYFILE" ]; then
        backup_file "$CADDYFILE" >/dev/null || return 1
    fi

    if [ -n "$email_line" ]; then
        cat > "$CADDYFILE" <<EOF
{
$email_line
}

EOF
    else
        : > "$CADDYFILE"
    fi

    cat >> "$CADDYFILE" <<EOF
import $CADDY_APPS_DIR/*.caddy
EOF

    chown root:caddy "$CADDYFILE"
    chmod 640 "$CADDYFILE"

    return 0
}

write_app_state() {
    local app_name="$1"
    local app_type="$2"
    local domain="$3"
    local upstream="$4"
    local extra="${5:-}"

    mkdir -p "$APPS_STATE_DIR"
    cat > "$APPS_STATE_DIR/${app_name}.conf" <<EOF
Name: $app_name
Type: $app_type
Domain: $domain
Upstream: $upstream
${extra}
CloudflareMode: orange-cloud-http01
CreatedAt: $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

confirm_overwrite_app() {
    local app_name="$1"
    local app_file="$CADDY_APPS_DIR/${app_name}.caddy"

    if [ ! -f "$app_file" ]; then
        return 0
    fi

    log_warning "应用反代已存在: $app_name"
    ask_yes_no "是否覆盖现有配置?" "n"
}

write_sui_app_caddyfile() {
    local app_name="$1"
    local app_file="$CADDY_APPS_DIR/${app_name}.caddy"
    local auth_block=""
    local subscription_path_matcher

    if [ "$CADDY_ENABLE_BASIC_AUTH" = "true" ]; then
        auth_block="        basic_auth argon2id {
            $CADDY_AUTH_USER $CADDY_AUTH_HASH
        }
"
    fi

    subscription_path_matcher="${CADDY_SUBSCRIPTION_PATH} ${CADDY_SUBSCRIPTION_PATH}/*"

    cat > "$app_file" <<EOF
$CADDY_DOMAIN {
    tls {
        issuer acme {
            disable_tlsalpn_challenge
        }
    }

    encode zstd gzip

    log {
        output file $CADDY_LOG_DIR/s-ui-access.log
    }

    @subscription path $subscription_path_matcher
    handle @subscription {
        reverse_proxy 127.0.0.1:$CADDY_SUBSCRIPTION_PORT
    }

    handle {
$auth_block        reverse_proxy 127.0.0.1:$CADDY_DASHBOARD_PORT
    }
}
EOF

    chown root:caddy "$app_file"
    chmod 640 "$app_file"
    write_app_state "$app_name" "s-ui" "$CADDY_DOMAIN" "127.0.0.1:$CADDY_DASHBOARD_PORT" "Subscription: $CADDY_SUBSCRIPTION_PATH -> 127.0.0.1:$CADDY_SUBSCRIPTION_PORT
BasicAuth: $CADDY_ENABLE_BASIC_AUTH"

    return 0
}

write_nezha_app_caddyfile() {
    local app_name="$1"
    local app_file="$CADDY_APPS_DIR/${app_name}.caddy"

    cat > "$app_file" <<EOF
$CADDY_DOMAIN {
    tls {
        issuer acme {
            disable_tlsalpn_challenge
        }
    }

    encode zstd gzip

    log {
        output file $CADDY_LOG_DIR/${app_name}-access.log
    }

    @grpcProto {
        path /proto.NezhaService/*
    }

    reverse_proxy @grpcProto {
        header_up Host {host}
        header_up nz-realip {http.CF-Connecting-IP}
        transport http {
            versions h2c
            read_buffer 4096
        }
        to 127.0.0.1:$CADDY_NEZHA_PORT
    }

    reverse_proxy {
        header_up Host {host}
        header_up Origin https://{host}
        header_up nz-realip {http.CF-Connecting-IP}
        transport http {
            read_buffer 16384
        }
        to 127.0.0.1:$CADDY_NEZHA_PORT
    }
}
EOF

    chown root:caddy "$app_file"
    chmod 640 "$app_file"
    write_app_state "$app_name" "nezha" "$CADDY_DOMAIN" "127.0.0.1:$CADDY_NEZHA_PORT" "Notes: Nezha V1 dashboard and agent communication share the same HTTP/gRPC port"

    return 0
}

write_custom_app_caddyfile() {
    local app_name="$1"
    local app_file="$CADDY_APPS_DIR/${app_name}.caddy"

    cat > "$app_file" <<EOF
$CADDY_DOMAIN {
    tls {
        issuer acme {
            disable_tlsalpn_challenge
        }
    }

    encode zstd gzip

    log {
        output file $CADDY_LOG_DIR/${app_name}-access.log
    }

    reverse_proxy $CADDY_CUSTOM_UPSTREAM
}
EOF

    chown root:caddy "$app_file"
    chmod 640 "$app_file"
    write_app_state "$app_name" "custom" "$CADDY_DOMAIN" "$CADDY_CUSTOM_UPSTREAM"

    return 0
}

validate_caddyfile() {
    if ! "$CADDY_BIN" validate --config "$CADDYFILE"; then
        log_error "Caddyfile 校验失败"
        return 1
    fi

    return 0
}

configure_ufw_for_caddy() {
    local port

    if ! command -v ufw >/dev/null 2>&1; then
        log_info "未安装 UFW,跳过防火墙规则配置"
        return 0
    fi

    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        log_info "UFW 未启用,跳过防火墙规则配置"
        return 0
    fi

    if ! ask_yes_no "检测到 UFW 已启用,是否开放 Caddy 所需的 80/tcp 和 443/tcp?" "y"; then
        log_warning "已跳过开放 80/443;Cloudflare 橙云回源和证书 HTTP-01 验证可能失败"
        return 0
    fi

    for port in 80 443; do
        if ufw status 2>/dev/null | grep -Eq "(^|[[:space:]])${port}/tcp"; then
            log_info "UFW 已存在 ${port}/tcp 规则"
            continue
        fi

        if ufw allow "${port}/tcp" comment 'Caddy HTTP/HTTPS' >/dev/null 2>&1; then
            log_success "已开放 ${port}/tcp"
        else
            log_warning "自动开放 ${port}/tcp 失败,请手动检查 UFW"
        fi
    done

    return 0
}

stop_legacy_npm_if_needed() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "nginx-proxy-manager"; then
        return 0
    fi

    log_warning "检测到 Nginx Proxy Manager 正在运行,它可能占用 443"

    if ! ask_yes_no "是否停止 Nginx Proxy Manager 并继续使用 Caddy?" "y"; then
        return 1
    fi

    if [ -d /opt/npm ] && [ -f /opt/npm/docker-compose.yml ]; then
        (cd /opt/npm && docker compose down) || return 1
    else
        docker stop nginx-proxy-manager >/dev/null 2>&1 || return 1
    fi

    log_success "Nginx Proxy Manager 已停止"
    return 0
}

check_caddy_ports_available() {
    local listeners
    local port

    if ! command -v ss >/dev/null 2>&1; then
        return 0
    fi

    for port in 80 443; do
        listeners="$(ss -H -tulpen 2>/dev/null | awk -v port="$port" '$5 ~ ":" port "$" || $5 ~ "\\]:" port "$" {print}')"

        if [ -z "$listeners" ]; then
            continue
        fi

        if echo "$listeners" | grep -qi "caddy"; then
            continue
        fi

        log_warning "检测到 ${port} 端口已被占用:"
        echo "$listeners" | sed 's/^/  /'

        ask_yes_no "是否仍继续? Caddy 启动或证书签发可能失败" "n" || return 1
    done

    return 0
}

start_or_reload_caddy() {
    systemctl daemon-reload
    systemctl enable caddy >/dev/null 2>&1

    if systemctl is-active --quiet caddy; then
        if systemctl reload caddy; then
            log_success "Caddy 已重载"
            return 0
        fi

        log_warning "Caddy reload 失败,尝试 restart"
    fi

    if ! systemctl restart caddy; then
        log_error "Caddy 启动失败"
        systemctl status caddy --no-pager -l 2>/dev/null || true
        return 1
    fi

    log_success "Caddy 已启动"
    return 0
}

verify_installation() {
    if ! command -v caddy >/dev/null 2>&1; then
        log_error "caddy 命令不存在"
        return 1
    fi

    if ! systemctl is-active --quiet caddy; then
        log_error "Caddy 服务未运行"
        return 1
    fi

    if ! wait_for_port localhost 80 20; then
        log_warning "80 端口暂未就绪,证书 HTTP-01 验证可能失败"
        return 1
    fi

    if ! wait_for_port localhost 443 20; then
        log_warning "443 端口暂未就绪,请检查 Caddy 日志"
        return 1
    fi

    return 0
}

write_install_flag() {
    local version
    version="$(caddy version 2>/dev/null | awk '{print $1}')"

    mkdir -p "$(dirname "$INSTALL_FLAG")"
    cat > "$INSTALL_FLAG" <<EOF
Version: ${version:-unknown}
Email: $CADDY_EMAIL
Caddyfile: $CADDYFILE
AppsDir: $CADDY_APPS_DIR
CloudflareMode: orange-cloud-http01
PublicPorts: 80/tcp 443/tcp
InstalledAt: $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

reset_app_config_defaults() {
    CADDY_DOMAIN=""
    CADDY_DASHBOARD_PORT="$DEFAULT_DASHBOARD_PORT"
    CADDY_SUBSCRIPTION_PORT="$DEFAULT_SUBSCRIPTION_PORT"
    CADDY_SUBSCRIPTION_PATH="$DEFAULT_SUBSCRIPTION_PATH"
    CADDY_NEZHA_PORT="$DEFAULT_NEZHA_PORT"
    CADDY_CUSTOM_UPSTREAM=""
    CADDY_SELECTED_APP_NAME=""
    CADDY_ENABLE_BASIC_AUTH="false"
    CADDY_AUTH_USER=""
    CADDY_AUTH_PASSWORD=""
    CADDY_AUTH_HASH=""
}

verify_caddy_service() {
    if ! command -v caddy >/dev/null 2>&1; then
        log_error "caddy 命令不存在"
        return 1
    fi

    if ! systemctl is-active --quiet caddy; then
        log_error "Caddy 服务未运行"
        return 1
    fi

    return 0
}

reload_caddy_config() {
    validate_caddyfile || return 1
    start_or_reload_caddy || return 1
    return 0
}

install_or_update_caddy_core() {
    log_info "开始安装/更新 Caddy 通用 HTTPS 入口..."

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    collect_global_email

    log_step 1 8 "停止旧 NPM 服务(如存在)"
    stop_legacy_npm_if_needed || return 1

    log_step 2 8 "检查 80/443 端口"
    check_caddy_ports_available || return 1

    log_step 3 8 "安装 Caddy 最新版"
    install_caddy_binary || return 1

    log_step 4 8 "创建运行用户和目录"
    ensure_caddy_user_and_dirs || return 1
    ensure_caddy_layout || return 1

    log_step 5 8 "写入 systemd 服务"
    write_systemd_service || return 1

    log_step 6 8 "生成 Caddy 主配置"
    write_main_caddyfile || return 1
    validate_caddyfile || return 1

    log_step 7 8 "配置防火墙"
    configure_ufw_for_caddy || return 1

    log_step 8 8 "启动 Caddy"
    start_or_reload_caddy || return 1
    verify_caddy_service || return 1
    write_install_flag

    log_success "Caddy 通用 HTTPS 入口已就绪"
    return 0
}

ensure_caddy_core_ready() {
    if ! command -v caddy >/dev/null 2>&1 || [ ! -f "$CADDY_SERVICE" ] || [ ! -f "$CADDYFILE" ]; then
        install_or_update_caddy_core || return 1
        return 0
    fi

    ensure_caddy_user_and_dirs || return 1
    ensure_caddy_layout || return 1
    write_systemd_service || return 1

    if ! grep -Fxq "import $CADDY_APPS_DIR/*.caddy" "$CADDYFILE" 2>/dev/null; then
        log_warning "当前 Caddyfile 未启用 apps.d 导入"
        if ! ask_yes_no "是否备份并切换为 VPS Tools 通用 Caddy 入口?" "y"; then
            return 1
        fi
        collect_global_email
        write_main_caddyfile || return 1
    fi

    reload_caddy_config || return 1
    write_install_flag
    return 0
}

show_app_post_install_info() {
    local app_name="$1"
    local app_type="$2"
    local title="$app_type HTTPS 入口配置完成"

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}$title${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}应用标识:${NC} $app_name
${BOLD}公网访问:${NC} ${CYAN}https://$CADDY_DOMAIN/${NC}
${BOLD}配置片段:${NC} $CADDY_APPS_DIR/${app_name}.caddy
${BOLD}状态记录:${NC} $APPS_STATE_DIR/${app_name}.conf

${BOLD}端口策略:${NC}
  Caddy 对公网只需要 80/tcp 和 443/tcp
  80 仅用于 ACME HTTP-01 证书验证和 HTTP->HTTPS 跳转
  应用自身端口建议只监听本机或内网

EOF
}

add_sui_proxy() {
    local app_name
    local default_app_name

    reset_app_config_defaults
    ensure_caddy_core_ready || return 1

    if ! check_sui_installed; then
        log_warning "未检测到 s-ui,建议先安装 s-ui 再配置反代"
        if ! ask_yes_no "是否仍继续添加 s-ui 入口?" "n"; then
            return 0
        fi
    fi

    collect_sui_proxy_config || return 1
    default_app_name="$(default_app_name_from_domain "$CADDY_DOMAIN")"
    prompt_app_name "$default_app_name" || return 1
    app_name="$CADDY_SELECTED_APP_NAME"

    if ! confirm_overwrite_app "$app_name"; then
        log_info "已取消添加 s-ui 入口"
        return 0
    fi

    hash_basic_auth_password || return 1
    write_sui_app_caddyfile "$app_name" || return 1
    reload_caddy_config || return 1
    show_post_install_info "$app_name"
    return 0
}

add_nezha_proxy() {
    local app_name
    local default_app_name

    reset_app_config_defaults
    ensure_caddy_core_ready || return 1

    if ! check_nezha_installed; then
        log_warning "未检测到 Nezha Dashboard,建议先安装 Nezha 再配置反代"
        if ! ask_yes_no "是否仍继续添加 Nezha 入口?" "n"; then
            return 0
        fi
    fi

    collect_nezha_proxy_config || return 1
    default_app_name="$(default_app_name_from_domain "$CADDY_DOMAIN")"
    prompt_app_name "$default_app_name" || return 1
    app_name="$CADDY_SELECTED_APP_NAME"

    if ! confirm_overwrite_app "$app_name"; then
        log_info "已取消添加 Nezha 入口"
        return 0
    fi

    write_nezha_app_caddyfile "$app_name" || return 1
    reload_caddy_config || return 1
    show_app_post_install_info "$app_name" "Nezha"
    return 0
}

add_custom_proxy() {
    local app_name
    local default_app_name

    reset_app_config_defaults
    ensure_caddy_core_ready || return 1
    collect_custom_proxy_config || return 1
    default_app_name="$(default_app_name_from_domain "$CADDY_DOMAIN")"
    prompt_app_name "$default_app_name" || return 1
    app_name="$CADDY_SELECTED_APP_NAME"

    if ! confirm_overwrite_app "$app_name"; then
        log_info "已取消添加自定义应用入口"
        return 0
    fi

    write_custom_app_caddyfile "$app_name" || return 1
    reload_caddy_config || return 1
    show_app_post_install_info "$app_name" "自定义应用"
    return 0
}

list_caddy_apps() {
    local state

    if [ ! -d "$APPS_STATE_DIR" ] || ! ls "$APPS_STATE_DIR"/*.conf >/dev/null 2>&1; then
        log_info "暂无由 VPS Tools 管理的 Caddy 应用入口"
        return 0
    fi

    echo
    echo -e "${BOLD}已管理的 Caddy 应用入口:${NC}"
    for state in "$APPS_STATE_DIR"/*.conf; do
        [ -f "$state" ] || continue
        echo
        grep -E "^(Name|Type|Domain|Upstream|Subscription|BasicAuth|CloudflareMode|PublicPorts|CreatedAt):" "$state" | sed 's/^/  /'
    done
    echo
}

delete_caddy_app() {
    local app_name
    local app_file
    local state_file

    list_caddy_apps
    printf "${BLUE}请输入要删除的应用标识: ${NC}"
    read -r app_name

    if [ -z "$app_name" ]; then
        log_info "已取消删除"
        return 0
    fi

    app_name="$(normalize_app_name "$app_name")"

    if ! is_valid_app_name "$app_name"; then
        log_error "应用标识无效"
        return 1
    fi

    app_file="$CADDY_APPS_DIR/${app_name}.caddy"
    state_file="$APPS_STATE_DIR/${app_name}.conf"

    if [ ! -f "$app_file" ] && [ ! -f "$state_file" ]; then
        log_warning "未找到应用入口: $app_name"
        return 0
    fi

    if ! ask_yes_no "确定删除 $app_name 的 Caddy 入口配置吗?" "n"; then
        log_info "已取消删除"
        return 0
    fi

    rm -f "$app_file" "$state_file"
    reload_caddy_config || return 1
    log_success "已删除应用入口: $app_name"
    return 0
}

show_caddy_manage_menu() {
    clear 2>/dev/null || true
    cat << EOF
${CYAN}================================================================${NC}
           ${BOLD}${GREEN}Caddy HTTPS 入口管理${NC}
${CYAN}================================================================${NC}

  ${BOLD}1${NC}. 安装/更新 Caddy 核心
  ${BOLD}2${NC}. 添加/更新 s-ui HTTPS 入口
  ${BOLD}3${NC}. 添加/更新 Nezha Dashboard 入口
  ${BOLD}4${NC}. 添加/更新自定义应用入口
  ${BOLD}5${NC}. 查看已管理入口
  ${BOLD}6${NC}. 删除应用入口
  ${BOLD}7${NC}. 校验并重载 Caddy

  ${BOLD}0${NC}. 返回主菜单

${CYAN}================================================================${NC}
EOF
}

manage() {
    local choice

    while true; do
        show_caddy_manage_menu
        printf "${BLUE}请输入选项 [0-7]: ${NC}"
        read -r choice

        case "$choice" in
            1)
                install_or_update_caddy_core
                pause_caddy_menu
                ;;
            2)
                add_sui_proxy
                pause_caddy_menu
                ;;
            3)
                add_nezha_proxy
                pause_caddy_menu
                ;;
            4)
                add_custom_proxy
                pause_caddy_menu
                ;;
            5)
                list_caddy_apps
                pause_caddy_menu
                ;;
            6)
                delete_caddy_app
                pause_caddy_menu
                ;;
            7)
                ensure_caddy_core_ready
                pause_caddy_menu
                ;;
            0)
                return 0
                ;;
            *)
                log_error "无效选项"
                pause_caddy_menu
                ;;
        esac
    done
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    if check_installed; then
        log_warning "$MODULE_NAME 已安装或已配置"
        if command -v caddy >/dev/null 2>&1; then
            log_info "当前版本: $(caddy version 2>/dev/null | awk '{print $1}')"
        fi

        if ask_yes_no "是否安装/更新 Caddy 核心到最新版?" "y"; then
            install_or_update_caddy_core || return 1
        else
            ensure_caddy_core_ready || return 1
        fi
    else
        install_or_update_caddy_core || return 1
    fi

    if check_sui_installed; then
        if ask_yes_no "是否现在添加/更新 s-ui HTTPS 入口?" "y"; then
            add_sui_proxy || return 1
        fi
    else
        log_warning "未检测到 s-ui;后续可在 Caddy 管理菜单中添加 s-ui 或其他应用入口"
    fi

    log_success "$MODULE_NAME 安装流程完成"
    return 0
}

# ============ 卸载函数 ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    if ! ask_yes_no "确定要卸载 Caddy 吗?"; then
        log_info "已取消卸载"
        return 0
    fi

    local keep_data=false
    if ask_yes_no "是否保留 Caddy 配置和证书数据?"; then
        keep_data=true
    fi

    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true
    rm -f "$CADDY_SERVICE"
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$CADDY_BIN" "$INSTALL_FLAG"

    if [ "$keep_data" = false ]; then
        rm -rf "$CADDY_DIR" "$CADDY_DATA_DIR" "$CADDY_LOG_DIR" "$APPS_STATE_DIR"
    fi

    log_success "$MODULE_NAME 已卸载"
}

# ============ 状态检查 ============
status() {
    if check_installed; then
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"

        if command -v caddy >/dev/null 2>&1; then
            echo "  版本: $(caddy version 2>/dev/null | awk '{print $1}')"
        fi

        if systemctl is-active --quiet caddy; then
            echo -e "  服务: ${GREEN}运行中${NC}"
        else
            echo -e "  服务: ${RED}已停止${NC}"
        fi

        if [ -f "$INSTALL_FLAG" ]; then
            grep -E "^(Email|Caddyfile|AppsDir|CloudflareMode|PublicPorts|InstalledAt):" "$INSTALL_FLAG" | sed 's/^/  /'
        fi

        if [ -d "$APPS_STATE_DIR" ] && ls "$APPS_STATE_DIR"/*.conf >/dev/null 2>&1; then
            echo "  应用入口:"
            for state in "$APPS_STATE_DIR"/*.conf; do
                [ -f "$state" ] || continue
                printf "    - "
                grep -E "^(Name|Type|Domain):" "$state" | paste -sd ' ' - | sed 's/Name: //; s/ Type: / (/; s/ Domain: /) /'
            done
        fi
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 安装后信息 ============
show_post_install_info() {
    local app_name="${1:-s-ui}"
    local auth_note="未启用"
    if [ "$CADDY_ENABLE_BASIC_AUTH" = "true" ]; then
        auth_note="已启用,用户名: $CADDY_AUTH_USER"
    fi

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Caddy + s-ui HTTPS 访问配置完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}公网访问:${NC}
  Dashboard: ${CYAN}https://$CADDY_DOMAIN/app/${NC}
  订阅入口: ${CYAN}https://$CADDY_DOMAIN$CADDY_SUBSCRIPTION_PATH${NC}

${BOLD}本地反代:${NC}
  Dashboard -> 127.0.0.1:$CADDY_DASHBOARD_PORT
  订阅     -> 127.0.0.1:$CADDY_SUBSCRIPTION_PORT
  Basic Auth: $auth_note
  应用标识 : $app_name

${BOLD}端口策略:${NC}
  开放 80/tcp 和 443/tcp
  80 仅用于 ACME HTTP-01 证书验证和 HTTP->HTTPS 跳转
  已禁用 TLS-ALPN challenge,适配 Cloudflare 橙云代理
  日常访问请使用 HTTPS

${BOLD}管理命令:${NC}
  ${CYAN}systemctl status caddy${NC}             # 查看服务状态
  ${CYAN}journalctl -u caddy -f${NC}             # 查看运行日志
  ${CYAN}caddy validate --config $CADDYFILE${NC} # 校验配置
  ${CYAN}systemctl reload caddy${NC}             # 重载配置

${BOLD}配置文件:${NC}
  Caddyfile: $CADDYFILE
  应用片段: $CADDY_APPS_DIR/${app_name}.caddy
  证书数据: $CADDY_DATA_DIR
  访问日志: $CADDY_LOG_DIR/s-ui-access.log

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# ============ 模块独立运行支持 ============
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    source "$SCRIPT_DIR/lib/common.sh"

    case "${1:-install}" in
        install) install ;;
        manage) manage ;;
        add-sui) add_sui_proxy ;;
        add-nezha) add_nezha_proxy ;;
        add-custom) add_custom_proxy ;;
        reload) reload_caddy_config ;;
        uninstall) uninstall ;;
        status) status ;;
        *) echo "用法: $0 {install|manage|add-sui|add-nezha|add-custom|reload|uninstall|status}"; exit 1 ;;
    esac
fi
