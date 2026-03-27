#!/bin/bash
# modules/install/s-ui.sh
# s-ui 安装模块

# ============ 模块元数据 ============
MODULE_NAME="s-ui"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="install"
MODULE_DESC="安装 s-ui 面板"

# ============ 全局变量 ============
UI_DIR="/usr/local/s-ui"
LEGACY_UI_DIR="/usr/local/x-ui"
UI_FLAG="$UI_DIR/installed.flag"
LEGACY_UI_FLAG="$LEGACY_UI_DIR/installed.flag"
INSTALL_FLAG="/var/log/vps-tools/install-s-ui.flag"

# ============ 检查函数 ============
check_installed() {
    command -v s-ui &>/dev/null || \
    command -v x-ui &>/dev/null || \
    [ -f "$UI_FLAG" ] || \
    [ -f "$LEGACY_UI_FLAG" ] || \
    [ -f "$INSTALL_FLAG" ]
}

check_dependencies() {
    return 0
}

is_valid_login_user() {
    local user="$1"
    if [ -z "$user" ]; then
        return 1
    fi
    if [ "$user" = "root" ]; then
        return 0
    fi
    id "$user" >/dev/null 2>&1
}

resolve_tunnel_user() {
    local user
    user=$(get_local_state "SSH_LOGIN_USER" 2>/dev/null || true)

    if [ -z "$user" ] && [ -f /var/log/vps-tools/init-03-ssh-config.flag ]; then
        user=$(grep "^User:" /var/log/vps-tools/init-03-ssh-config.flag | cut -d: -f2 | tr -d ' ')
    fi

    if is_valid_login_user "$user"; then
        echo "$user"
        return 0
    fi

    log_warning "未找到已保存的SSH登录用户"

    # 无保存信息时，提示用户输入并保存，供后续脚本复用
    while true; do
        printf "${BLUE}请输入用于SSH转发的用户名 [默认root]: ${NC}"
        read -r user
        user=${user:-root}

        if is_valid_login_user "$user"; then
            if [ "$user" = "root" ]; then
                set_local_state "SSH_LOGIN_MODE" "root" || true
            else
                set_local_state "SSH_LOGIN_MODE" "create-user" || true
            fi
            set_local_state "SSH_LOGIN_USER" "$user" || true
            echo "$user"
            return 0
        fi

        log_error "用户不存在: $user"
    done
}

is_valid_ssh_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

resolve_tunnel_port() {
    local port
    port=$(get_local_state "SSH_PORT" 2>/dev/null || true)

    if [ -z "$port" ] && [ -f /var/log/vps-tools/init-03-ssh-config.flag ]; then
        port=$(grep "^Port:" /var/log/vps-tools/init-03-ssh-config.flag | cut -d: -f2 | tr -d ' ')
    fi

    if is_valid_ssh_port "$port"; then
        echo "$port"
        return 0
    fi

    # 没有保存端口时提示输入并保存
    while true; do
        printf "${BLUE}请输入SSH端口 [默认22]: ${NC}"
        read -r port
        port=${port:-22}

        if is_valid_ssh_port "$port"; then
            set_local_state "SSH_PORT" "$port" || true
            echo "$port"
            return 0
        fi

        log_error "端口无效: $port"
    done
}

resolve_tunnel_key_path() {
    local ssh_user="$1"
    local key_path
    key_path=$(get_local_state "SSH_KEY_PATH" 2>/dev/null || true)

    if [ -z "$key_path" ]; then
        key_path="~/.ssh/${ssh_user}_ed25519"
    fi

    set_local_state "SSH_KEY_PATH" "$key_path" || true
    echo "$key_path"
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    if check_installed; then
        log_warning "$MODULE_NAME 可能已安装"
        if ! ask_yes_no "是否重新安装?"; then
            return 0
        fi
    fi

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    # 让用户指定版本 (留空则安装最新版)
    local sui_version
    printf "${BLUE}请输入s-ui版本号 (留空安装最新版, 例如v1.3.11): ${NC}"
    read -r sui_version

    local download_branch="master"
    local install_args=""

    if [ -n "$sui_version" ]; then
        # 确保版本号以v开头
        if [[ ! "$sui_version" =~ ^v ]]; then
            sui_version="v${sui_version}"
        fi
        download_branch="$sui_version"
        install_args="$sui_version"
        log_success "将安装版本: $sui_version"
    else
        sui_version="latest"
        log_success "将安装最新版"
    fi

    log_step 1 4 "下载安装脚本 ($sui_version)"
    local install_script="/tmp/s-ui_install.sh"
    local download_url="https://raw.githubusercontent.com/alireza0/s-ui/${download_branch}/install.sh"

    if ! curl -Ls -o "$install_script" "$download_url"; then
        log_error "下载安装脚本失败 (版本: $sui_version)"
        log_info "请检查版本号是否正确: https://github.com/alireza0/s-ui/releases"
        return 1
    fi

    # 检查下载的文件是否有效 (非空且是shell脚本)
    if [ ! -s "$install_script" ] || ! head -1 "$install_script" | grep -q "#!/"; then
        log_error "下载的安装脚本无效,请检查版本号: $sui_version"
        rm -f "$install_script"
        return 1
    fi

    log_step 2 4 "设置执行权限"
    chmod +x "$install_script"

    log_step 3 4 "执行安装脚本 ($sui_version)"
    log_warning "安装过程需要交互,请按提示操作"
    echo

    if ! bash "$install_script" $install_args; then
        log_error "安装失败"
        rm -f "$install_script"
        return 1
    fi

    log_step 4 4 "清理临时文件"
    rm -f "$install_script"

    # 创建标记
    mkdir -p "$UI_DIR"
    touch "$UI_FLAG"
    mkdir -p "$(dirname "$INSTALL_FLAG")"
    cat > "$INSTALL_FLAG" <<EOF
Version: $sui_version
InstalledAt: $(date '+%Y-%m-%d %H:%M:%S')
EOF

    log_success "$MODULE_NAME $sui_version 安装完成!"
    show_post_install_info

    return 0
}

# ============ 卸载函数 ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    if command -v s-ui &>/dev/null; then
        log_info "使用官方卸载方法..."
        s-ui uninstall
    elif command -v x-ui &>/dev/null; then
        log_warning "检测到旧版 x-ui,使用旧命令卸载..."
        x-ui uninstall
    else
        log_warning "找不到 s-ui 命令,手动清理..."
        rm -rf "$UI_DIR" "$LEGACY_UI_DIR"
        systemctl stop s-ui 2>/dev/null || true
        systemctl disable s-ui 2>/dev/null || true
        systemctl stop x-ui 2>/dev/null || true
        systemctl disable x-ui 2>/dev/null || true
    fi

    rm -f "$UI_FLAG" "$LEGACY_UI_FLAG" "$INSTALL_FLAG"
    log_success "$MODULE_NAME 卸载完成"
}

# ============ 状态检查 ============
status() {
    if check_installed; then
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"

        if systemctl is-active --quiet s-ui || systemctl is-active --quiet x-ui; then
            echo -e "  状态: ${GREEN}运行中${NC}"
        else
            echo -e "  状态: ${RED}已停止${NC}"
        fi
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 安装后信息 ============
show_post_install_info() {
    local ip
    local ssh_user
    local ssh_port
    local ssh_key_path
    ip=$(get_server_ip)
    ssh_user=$(resolve_tunnel_user)
    ssh_port=$(resolve_tunnel_port)
    ssh_key_path=$(resolve_tunnel_key_path "$ssh_user")

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}s-ui 安装完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}管理命令:${NC}
  ${CYAN}s-ui${NC}                    # 打开管理菜单
  ${CYAN}s-ui start${NC}              # 启动面板
  ${CYAN}s-ui stop${NC}               # 停止面板
  ${CYAN}s-ui restart${NC}            # 重启面板
  ${CYAN}s-ui status${NC}             # 查看状态

${YELLOW}${BOLD}提示:${NC}
  请使用 's-ui' 命令查看面板访问地址和凭据

${BOLD}本地SSH转发(避免明文访问HTTP后台):${NC}
  ssh -L 2095:127.0.0.1:2095 -p ${ssh_port} -i ${ssh_key_path} ${ssh_user}@${ip}
  http://127.0.0.1:2095/app/
  (如果与你环境不一致,请把用户名/IP/端口/密钥路径替换成实际值)

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
