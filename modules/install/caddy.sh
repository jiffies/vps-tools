#!/bin/bash
# modules/install/caddy.sh
# Caddy 安装与 s-ui HTTPS 反代配置模块
#
# 功能:
# - 从 Caddy 官方下载接口安装最新版静态二进制
# - 创建 systemd 服务,由非 root 的 caddy 用户运行
# - 生成适配 Cloudflare 橙云的 Caddyfile,通过 HTTP-01 自动签发源站证书
# - 反代 s-ui dashboard(默认 2095) 和订阅端口(默认 2096)

# ============ 模块元数据 ============
MODULE_NAME="Caddy"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="install"
MODULE_DESC="安装 Caddy 并配置 s-ui HTTPS 访问"

# ============ 全局变量 ============
CADDY_BIN="/usr/local/bin/caddy"
CADDY_DIR="/etc/caddy"
CADDYFILE="$CADDY_DIR/Caddyfile"
CADDY_SERVICE="/etc/systemd/system/caddy.service"
CADDY_DATA_DIR="/var/lib/caddy"
CADDY_LOG_DIR="/var/log/caddy"
INSTALL_FLAG="/var/log/vps-tools/install-caddy.flag"
CADDY_DOWNLOAD_BASE="https://caddyserver.com/api/download"

DEFAULT_DASHBOARD_PORT="2095"
DEFAULT_SUBSCRIPTION_PORT="2096"
DEFAULT_SUBSCRIPTION_PATH="/sub"

CADDY_DOMAIN=""
CADDY_EMAIL=""
CADDY_DASHBOARD_PORT="$DEFAULT_DASHBOARD_PORT"
CADDY_SUBSCRIPTION_PORT="$DEFAULT_SUBSCRIPTION_PORT"
CADDY_SUBSCRIPTION_PATH="$DEFAULT_SUBSCRIPTION_PATH"
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

collect_proxy_config() {
    local domain
    local email
    local port
    local path

    show_domain_notice

    while true; do
        printf "${BLUE}请输入用于访问 s-ui 的域名: ${NC}"
        read -r domain
        domain="$(echo "$domain" | tr '[:upper:]' '[:lower:]')"

        if is_valid_public_domain "$domain"; then
            CADDY_DOMAIN="$domain"
            break
        fi

        log_error "域名无效,示例: panel.example.com"
    done

    if ! confirm_cloudflare_dns_ready "$CADDY_DOMAIN"; then
        log_info "已取消 Caddy 配置"
        return 1
    fi

    printf "${BLUE}请输入 ACME 通知邮箱 (可留空): ${NC}"
    read -r email
    if [ -n "$email" ]; then
        if validate_email "$email"; then
            CADDY_EMAIL="$email"
        else
            log_warning "邮箱格式无效,将不写入 ACME 邮箱"
        fi
    fi

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

    mkdir -p "$CADDY_DIR" "$CADDY_DATA_DIR" "$CADDY_LOG_DIR"
    chown root:caddy "$CADDY_DIR"
    chmod 755 "$CADDY_DIR"
    chown -R caddy:caddy "$CADDY_DATA_DIR" "$CADDY_LOG_DIR"

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

write_caddyfile() {
    local email_line=""
    local auth_block=""
    local subscription_path_matcher

    if [ -n "$CADDY_EMAIL" ]; then
        email_line="    email $CADDY_EMAIL"
    fi

    if [ "$CADDY_ENABLE_BASIC_AUTH" = "true" ]; then
        auth_block="        basic_auth argon2id {
            $CADDY_AUTH_USER $CADDY_AUTH_HASH
        }
"
    fi

    subscription_path_matcher="${CADDY_SUBSCRIPTION_PATH} ${CADDY_SUBSCRIPTION_PATH}/*"

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

    chown root:caddy "$CADDYFILE"
    chmod 640 "$CADDYFILE"

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
Domain: $CADDY_DOMAIN
Dashboard: 127.0.0.1:$CADDY_DASHBOARD_PORT
Subscription: $CADDY_SUBSCRIPTION_PATH -> 127.0.0.1:$CADDY_SUBSCRIPTION_PORT
BasicAuth: $CADDY_ENABLE_BASIC_AUTH
CloudflareMode: orange-cloud-http01
PublicPorts: 80/tcp 443/tcp
InstalledAt: $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    if check_installed; then
        log_warning "$MODULE_NAME 已安装或已配置"
        if command -v caddy >/dev/null 2>&1; then
            log_info "当前版本: $(caddy version 2>/dev/null | awk '{print $1}')"
        fi

        if ! ask_yes_no "是否重新安装最新版并重新配置 s-ui 反代?"; then
            return 0
        fi
    fi

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    if ! check_sui_installed; then
        log_warning "未检测到 s-ui,建议先安装 s-ui 再配置 Caddy 反代"
        if ! ask_yes_no "是否仍继续配置 Caddy?" "n"; then
            return 0
        fi
    fi

    collect_proxy_config || return 1

    log_step 1 8 "停止旧 NPM 服务(如存在)"
    stop_legacy_npm_if_needed || return 1

    log_step 2 8 "检查 80/443 端口"
    check_caddy_ports_available || return 1

    log_step 3 8 "安装 Caddy 最新版"
    install_caddy_binary || return 1

    log_step 4 8 "创建运行用户和目录"
    ensure_caddy_user_and_dirs || return 1

    log_step 5 8 "写入 systemd 服务"
    write_systemd_service || return 1

    log_step 6 8 "生成 Caddyfile"
    hash_basic_auth_password || return 1
    write_caddyfile || return 1
    validate_caddyfile || return 1

    log_step 7 8 "配置防火墙"
    configure_ufw_for_caddy || return 1

    log_step 8 8 "启动 Caddy"
    start_or_reload_caddy || return 1

    if verify_installation; then
        write_install_flag
        log_success "$MODULE_NAME 安装和 s-ui 反代配置完成!"
        show_post_install_info
        return 0
    fi

    return 1
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
        rm -rf "$CADDY_DIR" "$CADDY_DATA_DIR" "$CADDY_LOG_DIR"
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
            grep -E "^(Domain|Dashboard|Subscription|BasicAuth|CloudflareMode|PublicPorts):" "$INSTALL_FLAG" | sed 's/^/  /'
        fi
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 安装后信息 ============
show_post_install_info() {
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
        uninstall) uninstall ;;
        status) status ;;
        *) echo "用法: $0 {install|uninstall|status}"; exit 1 ;;
    esac
fi
