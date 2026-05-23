#!/bin/bash
# modules/install/nezha.sh
# Nezha Dashboard 安装模块

# ============ 模块元数据 ============
MODULE_NAME="Nezha"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="install"
MODULE_DESC="安装 Nezha Dashboard/Agent"

# ============ 全局变量 ============
NEZHA_BASE_DIR="/opt/nezha"
NEZHA_DASHBOARD_DIR="$NEZHA_BASE_DIR/dashboard"
NEZHA_AGENT_DIR="$NEZHA_BASE_DIR/agent"
NEZHA_MANAGER_SCRIPT="$NEZHA_BASE_DIR/nezha.sh"
NEZHA_AGENT_SCRIPT="$NEZHA_BASE_DIR/agent.sh"
NEZHA_AGENT_BIN="$NEZHA_AGENT_DIR/nezha-agent"
NEZHA_SERVICE="nezha-dashboard"
NEZHA_CONFIG="$NEZHA_DASHBOARD_DIR/data/config.yaml"
NEZHA_COMPOSE_FILE="$NEZHA_DASHBOARD_DIR/docker-compose.yaml"
INSTALL_FLAG="/var/log/vps-tools/install-nezha.flag"
NEZHA_SCRIPT_URL="https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh"
NEZHA_AGENT_SCRIPT_URL="https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh"
NEZHA_INSTALL_MODE=""
NEZHA_ROLE=""
NEZHA_AGENT_SERVER=""
NEZHA_AGENT_TLS="false"
NEZHA_AGENT_SECRET=""
NEZHA_AGENT_UUID=""

# ============ 检查函数 ============
check_dashboard_installed() {
    [ -f "$NEZHA_COMPOSE_FILE" ] || \
    [ -f "$NEZHA_DASHBOARD_DIR/app" ] || \
    systemctl list-unit-files 2>/dev/null | grep -q "^${NEZHA_SERVICE}.service"
}

check_agent_installed() {
    [ -x "$NEZHA_AGENT_BIN" ] || \
    systemctl list-units --type=service --all 2>/dev/null | grep -q "nezha-agent"
}

check_real_installed() {
    check_dashboard_installed || check_agent_installed
}

check_installed() {
    [ -f "$INSTALL_FLAG" ] || check_real_installed
}

check_dependencies() {
    return 0
}

detect_install_mode() {
    if [ -f "$NEZHA_COMPOSE_FILE" ]; then
        echo "docker"
        return 0
    fi

    if [ -f "$NEZHA_DASHBOARD_DIR/app" ] || systemctl list-unit-files 2>/dev/null | grep -q "^${NEZHA_SERVICE}.service"; then
        echo "standalone"
        return 0
    fi

    echo "unknown"
}

detect_dashboard_port() {
    if [ -f "$NEZHA_CONFIG" ]; then
        sed -n 's/.*listen_port:[[:space:]]*\([0-9]\+\).*/\1/p' "$NEZHA_CONFIG" | head -1
    fi
}

detect_agent_hostport() {
    if [ -f "$NEZHA_CONFIG" ]; then
        sed -n 's/.*install_host:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$NEZHA_CONFIG" | head -1
    fi
}

detect_agent_server() {
    local config

    for config in "$NEZHA_AGENT_DIR"/*config*.yml "$NEZHA_AGENT_DIR/config.yml"; do
        [ -f "$config" ] || continue
        sed -n 's/^server:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$config" | head -1
        return 0
    done
}

download_nezha_script() {
    local tmp_script
    tmp_script="$(mktemp)"

    log_info "下载 Nezha 官方安装脚本: $NEZHA_SCRIPT_URL"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL --connect-timeout 15 --retry 3 -o "$tmp_script" "$NEZHA_SCRIPT_URL"; then
            rm -f "$tmp_script"
            log_error "下载 Nezha 官方安装脚本失败"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q -O "$tmp_script" "$NEZHA_SCRIPT_URL"; then
            rm -f "$tmp_script"
            log_error "下载 Nezha 官方安装脚本失败"
            return 1
        fi
    else
        rm -f "$tmp_script"
        log_error "缺少 curl 或 wget,无法下载 Nezha 官方安装脚本"
        return 1
    fi

    if [ ! -s "$tmp_script" ] || ! head -1 "$tmp_script" | grep -q "#!/"; then
        rm -f "$tmp_script"
        log_error "下载的 Nezha 安装脚本无效"
        return 1
    fi

    mkdir -p "$NEZHA_BASE_DIR"
    command install -m 0755 "$tmp_script" "$NEZHA_MANAGER_SCRIPT" || {
        rm -f "$tmp_script"
        log_error "保存 Nezha 管理脚本失败"
        return 1
    }
    rm -f "$tmp_script"

    log_success "Nezha 管理脚本已保存: $NEZHA_MANAGER_SCRIPT"
    return 0
}

download_agent_script() {
    local tmp_script
    tmp_script="$(mktemp)"

    log_info "下载 Nezha Agent 官方安装脚本: $NEZHA_AGENT_SCRIPT_URL"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL --connect-timeout 15 --retry 3 -o "$tmp_script" "$NEZHA_AGENT_SCRIPT_URL"; then
            rm -f "$tmp_script"
            log_error "下载 Nezha Agent 官方安装脚本失败"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q -O "$tmp_script" "$NEZHA_AGENT_SCRIPT_URL"; then
            rm -f "$tmp_script"
            log_error "下载 Nezha Agent 官方安装脚本失败"
            return 1
        fi
    else
        rm -f "$tmp_script"
        log_error "缺少 curl 或 wget,无法下载 Nezha Agent 官方安装脚本"
        return 1
    fi

    if [ ! -s "$tmp_script" ] || ! head -1 "$tmp_script" | grep -q "#!/"; then
        rm -f "$tmp_script"
        log_error "下载的 Nezha Agent 安装脚本无效"
        return 1
    fi

    mkdir -p "$NEZHA_BASE_DIR"
    command install -m 0755 "$tmp_script" "$NEZHA_AGENT_SCRIPT" || {
        rm -f "$tmp_script"
        log_error "保存 Nezha Agent 安装脚本失败"
        return 1
    }
    rm -f "$tmp_script"

    log_success "Nezha Agent 安装脚本已保存: $NEZHA_AGENT_SCRIPT"
    return 0
}

ensure_manager_script() {
    if [ -x "$NEZHA_MANAGER_SCRIPT" ]; then
        return 0
    fi

    download_nezha_script
}

ensure_agent_script() {
    if [ -x "$NEZHA_AGENT_SCRIPT" ]; then
        return 0
    fi

    download_agent_script
}

select_nezha_role() {
    local choice

    echo
    echo -e "${BOLD}请选择 Nezha 安装角色:${NC}"
    echo "  1. 服务端 Dashboard (监控面板)"
    echo "  2. 客户端 Agent (被监控节点)"
    echo

    while true; do
        printf "${BLUE}请输入选项 [1-2, 默认1]: ${NC}"
        read -r choice
        choice=${choice:-1}

        case "$choice" in
            1)
                NEZHA_ROLE="dashboard"
                return 0
                ;;
            2)
                NEZHA_ROLE="agent"
                return 0
                ;;
            *)
                log_error "请输入 1 或 2"
                ;;
        esac
    done
}

select_install_mode() {
    local default_mode="2"
    local choice

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        default_mode="1"
    fi

    echo
    echo -e "${BOLD}请选择 Nezha Dashboard 安装方式:${NC}"
    echo "  1. Docker (推荐已有 Docker 的 VPS)"
    echo "  2. 独立安装"
    echo

    while true; do
        printf "${BLUE}请输入选项 [1-2, 默认%s]: ${NC}" "$default_mode"
        read -r choice
        choice=${choice:-$default_mode}

        case "$choice" in
            1)
                NEZHA_INSTALL_MODE="1"
                return 0
                ;;
            2)
                NEZHA_INSTALL_MODE="0"
                return 0
                ;;
            *)
                log_error "请输入 1 或 2"
                ;;
        esac
    done
}

run_official_script() {
    local action="$1"
    local mode="${2:-}"

    if [ -n "$mode" ]; then
        (cd "$NEZHA_BASE_DIR" && IS_DOCKER_NEZHA="$mode" bash "$NEZHA_MANAGER_SCRIPT" "$action")
    else
        (cd "$NEZHA_BASE_DIR" && bash "$NEZHA_MANAGER_SCRIPT" "$action")
    fi
}

run_agent_script() {
    (cd "$NEZHA_BASE_DIR" && \
        NZ_SERVER="$NEZHA_AGENT_SERVER" \
        NZ_TLS="$NEZHA_AGENT_TLS" \
        NZ_CLIENT_SECRET="$NEZHA_AGENT_SECRET" \
        NZ_UUID="$NEZHA_AGENT_UUID" \
        bash "$NEZHA_AGENT_SCRIPT")
}

write_install_flag() {
    local mode
    local port
    local hostport
    local agent_server
    mode="$(detect_install_mode)"
    port="$(detect_dashboard_port)"
    hostport="$(detect_agent_hostport)"
    agent_server="$(detect_agent_server)"

    mkdir -p "$(dirname "$INSTALL_FLAG")"
    cat > "$INSTALL_FLAG" <<EOF
DashboardInstalled: $(check_dashboard_installed && echo yes || echo no)
AgentInstalled: $(check_agent_installed && echo yes || echo no)
DashboardMode: $mode
DashboardDir: $NEZHA_DASHBOARD_DIR
AgentDir: $NEZHA_AGENT_DIR
ManagerScript: $NEZHA_MANAGER_SCRIPT
DashboardPort: ${port:-unknown}
AgentHostPort: ${hostport:-unknown}
AgentServer: ${agent_server:-unknown}
InstalledAt: $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

show_install_notes() {
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Nezha Dashboard 安装提示${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
官方脚本会继续询问站点标题、暴露端口、Agent 连接地址、TLS 和语言。

建议:
  - Dashboard 暴露端口默认使用 ${GREEN}8008${NC}
  - 如果后续用 Caddy 统一公网入口,应用本体端口无需直接开放到公网
  - 安装完成后,可进入 ${CYAN}13. Caddy HTTPS入口管理${NC} 添加 Nezha 入口

EOF
}

collect_agent_config() {
    local input

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Nezha Agent 安装配置${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
请先在 Dashboard 的服务器页面创建/选择服务器,复制安装命令中的:
  NZ_SERVER、NZ_TLS、NZ_CLIENT_SECRET、NZ_UUID

EOF

    while true; do
        printf "${BLUE}Dashboard 通信地址 NZ_SERVER (例如 data.example.com:8008): ${NC}"
        read -r NEZHA_AGENT_SERVER
        if [ -n "$NEZHA_AGENT_SERVER" ] && [[ "$NEZHA_AGENT_SERVER" != *" "* ]] && [[ "$NEZHA_AGENT_SERVER" == *:* ]]; then
            break
        fi
        log_error "通信地址无效,请使用 域名或IP:端口"
    done

    if ask_yes_no "Agent 是否通过 TLS 连接 Dashboard? (对应 NZ_TLS)" "n"; then
        NEZHA_AGENT_TLS="true"
    else
        NEZHA_AGENT_TLS="false"
    fi

    while true; do
        printf "${BLUE}NZ_CLIENT_SECRET: ${NC}"
        read -r -s NEZHA_AGENT_SECRET
        echo
        if [ -n "$NEZHA_AGENT_SECRET" ]; then
            break
        fi
        log_error "NZ_CLIENT_SECRET 不能为空"
    done

    while true; do
        printf "${BLUE}NZ_UUID: ${NC}"
        read -r input
        if [ -n "$input" ]; then
            NEZHA_AGENT_UUID="$input"
            break
        fi
        log_error "NZ_UUID 不能为空,请从 Dashboard 生成的安装命令中复制"
    done
}

install_dashboard() {
    local mode

    log_info "开始安装 Nezha Dashboard..."

    if check_dashboard_installed; then
        log_warning "Nezha Dashboard 可能已安装"
        if ! ask_yes_no "是否继续执行官方安装/管理脚本?" "n"; then
            return 0
        fi
    fi

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    log_step 1 4 "下载 Nezha 官方管理脚本"
    download_nezha_script || return 1

    log_step 2 4 "选择安装方式"
    select_install_mode || return 1
    mode="$NEZHA_INSTALL_MODE"

    log_step 3 4 "执行官方安装流程"
    show_install_notes
    run_official_script "install" "$mode" || return 1

    log_step 4 4 "记录安装状态"
    if check_installed; then
        write_install_flag
        log_success "$MODULE_NAME Dashboard 安装流程完成!"
        show_post_install_info
        return 0
    fi

    log_warning "未检测到 Nezha Dashboard 安装结果,可能是在官方脚本中取消了安装"
    return 0
}

install_agent() {
    log_info "开始安装 Nezha Agent..."

    if check_agent_installed; then
        log_warning "Nezha Agent 可能已安装"
        if ! ask_yes_no "是否继续重新安装/添加 Agent 配置?" "n"; then
            return 0
        fi
    fi

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    log_step 1 4 "下载 Nezha Agent 官方安装脚本"
    download_agent_script || return 1

    log_step 2 4 "填写 Agent 连接配置"
    collect_agent_config || return 1

    log_step 3 4 "执行官方 Agent 安装流程"
    run_agent_script || return 1
    NEZHA_AGENT_SECRET=""

    log_step 4 4 "记录安装状态"
    if check_agent_installed; then
        write_install_flag
        log_success "$MODULE_NAME Agent 安装流程完成!"
        show_post_install_info
        return 0
    fi

    log_warning "未检测到 Nezha Agent 安装结果,请检查官方脚本输出"
    return 0
}

# ============ 安装函数 ============
install() {
    select_nezha_role || return 1

    case "$NEZHA_ROLE" in
        dashboard) install_dashboard ;;
        agent) install_agent ;;
        *) log_error "未知 Nezha 角色: $NEZHA_ROLE"; return 1 ;;
    esac
}

# ============ 卸载函数 ============
uninstall() {
    local mode
    local choice

    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    echo
    echo -e "${BOLD}请选择要卸载的 Nezha 组件:${NC}"
    echo "  1. 服务端 Dashboard"
    echo "  2. 客户端 Agent"
    echo "  3. 全部"
    echo
    printf "${BLUE}请输入选项 [1-3, 默认3]: ${NC}"
    read -r choice
    choice=${choice:-3}

    if [ "$choice" != "1" ] && [ "$choice" != "2" ] && [ "$choice" != "3" ]; then
        log_error "无效选项: $choice"
        return 1
    fi

    if [ "$choice" = "1" ] || [ "$choice" = "3" ]; then
        if check_dashboard_installed; then
            ensure_manager_script || return 1
            mode="$(detect_install_mode)"
            case "$mode" in
                docker) mode="1" ;;
                standalone) mode="0" ;;
                *) mode="" ;;
            esac
            run_official_script "uninstall" "$mode" || return 1
        else
            log_info "未检测到 Nezha Dashboard"
        fi
    fi

    if [ "$choice" = "2" ] || [ "$choice" = "3" ]; then
        if check_agent_installed; then
            ensure_agent_script || return 1
            (cd "$NEZHA_BASE_DIR" && bash "$NEZHA_AGENT_SCRIPT" uninstall) || return 1
        else
            log_info "未检测到 Nezha Agent"
        fi
    fi

    if ! check_real_installed; then
        rm -f "$INSTALL_FLAG"
        log_success "$MODULE_NAME 已卸载"
    else
        write_install_flag
        log_warning "$MODULE_NAME 仍有组件可检测到,请检查官方脚本输出"
    fi
}

# ============ 管理函数 ============
manage() {
    ensure_manager_script || return 1
    (cd "$NEZHA_BASE_DIR" && bash "$NEZHA_MANAGER_SCRIPT")
}

# ============ 状态检查 ============
status() {
    local mode
    local port
    local hostport
    local agent_server

    if check_installed; then
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"

        if check_dashboard_installed; then
            mode="$(detect_install_mode)"
            port="$(detect_dashboard_port)"
            hostport="$(detect_agent_hostport)"
            echo "  Dashboard: 已安装"
            echo "  Dashboard模式: $mode"
            [ -n "$port" ] && echo "  Dashboard端口: $port"
            [ -n "$hostport" ] && echo "  Agent连接地址: $hostport"

            if systemctl is-active --quiet "$NEZHA_SERVICE"; then
                echo -e "  Dashboard服务: ${GREEN}运行中${NC}"
            elif command -v docker >/dev/null 2>&1 && docker ps --format '{{.Image}} {{.Names}}' 2>/dev/null | grep -qi "nezha"; then
                echo -e "  Dashboard Docker: ${GREEN}运行中${NC}"
            else
                echo -e "  Dashboard状态: ${YELLOW}未确认运行${NC}"
            fi
        fi

        if check_agent_installed; then
            agent_server="$(detect_agent_server)"
            echo "  Agent: 已安装"
            [ -n "$agent_server" ] && echo "  Agent连接: $agent_server"

            if systemctl list-units --type=service --all 2>/dev/null | grep -q "nezha-agent" &&
               systemctl is-active --quiet "$(systemctl list-units --type=service --all 2>/dev/null | awk '/nezha-agent/ {print $1; exit}')"; then
                echo -e "  Agent服务: ${GREEN}运行中${NC}"
            else
                echo -e "  Agent状态: ${YELLOW}未确认运行${NC}"
            fi
        fi

        if ! check_dashboard_installed && ! check_agent_installed; then
            echo -e "  状态: ${YELLOW}仅发现安装标记,未检测到组件${NC}"
        else
            :
        fi
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 安装后信息 ============
show_post_install_info() {
    local port
    local agent_server
    port="$(detect_dashboard_port)"
    agent_server="$(detect_agent_server)"

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Nezha 安装流程完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    if check_dashboard_installed; then
        cat << EOF
${BOLD}本地访问:${NC}
  http://127.0.0.1:${port:-8008}/dashboard

${BOLD}后续公网入口:${NC}
  进入 ${CYAN}13. Caddy HTTPS入口管理${NC}
  选择 ${CYAN}添加/更新 Nezha Dashboard 入口${NC}

EOF
    fi

    if check_agent_installed; then
        cat << EOF
${BOLD}Agent:${NC}
  已安装为被监控节点
  Dashboard连接: ${agent_server:-请在Agent配置中查看}

EOF
    fi

    cat << EOF
${BOLD}管理命令:${NC}
  ${CYAN}$NEZHA_MANAGER_SCRIPT${NC}      # 打开官方管理菜单
  ${CYAN}$NEZHA_AGENT_SCRIPT${NC}        # Agent官方安装脚本
  ${CYAN}systemctl status nezha-dashboard${NC}  # 独立安装服务状态

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
        uninstall) uninstall ;;
        status) status ;;
        *) echo "用法: $0 {install|manage|uninstall|status}"; exit 1 ;;
    esac
fi
