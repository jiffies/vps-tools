#!/bin/bash
# modules/install/tailscale.sh
# Tailscale 安装模块
#
# input: lib/common.sh (日志、输入、网络等通用函数)
# output: 安装/卸载/状态查询 Tailscale VPN
# 地位: 应用安装模块，提供 Tailscale 网络组件的生命周期管理
#
# 一旦我被更新，请务必同时更新我的开头注释，以及所属目录的md。

# ============ 模块元数据 ============
MODULE_NAME="Tailscale"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="install"
MODULE_DESC="安装 Tailscale VPN 组网工具"

# ============ 全局变量 ============
INSTALL_FLAG="/var/log/vps-tools/install-tailscale.flag"

# ============ 检查函数 ============
check_installed() {
    command -v tailscale &>/dev/null || [ -f "$INSTALL_FLAG" ]
}

check_dependencies() {
    return 0
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    if check_installed; then
        log_warning "$MODULE_NAME 已安装"
        local version
        version=$(tailscale version 2>/dev/null | head -1)
        log_info "当前版本: ${version:-未知}"

        if ! ask_yes_no "是否重新安装?"; then
            return 0
        fi
    fi

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    # 步骤1: 下载并执行官方安装脚本
    log_step 1 3 "下载并安装 Tailscale"
    log_info "使用官方安装脚本: https://tailscale.com/install.sh"

    if ! curl -fsSL https://tailscale.com/install.sh | sh; then
        log_error "Tailscale 安装失败"
        return 1
    fi

    # 步骤2: 启动服务
    log_step 2 3 "启动 Tailscale 服务"
    systemctl enable --now tailscaled >/dev/null 2>&1

    if ! systemctl is-active tailscaled >/dev/null 2>&1; then
        log_error "Tailscale 服务启动失败"
        return 1
    fi
    log_success "Tailscale 服务已启动"

    # 步骤3: 引导用户登录
    log_step 3 3 "登录 Tailscale 网络"
    log_info "正在启动 Tailscale 认证..."
    echo

    tailscale up
    local up_result=$?

    if [ $up_result -ne 0 ]; then
        log_warning "Tailscale 认证未完成,可稍后运行 'tailscale up' 重试"
    fi

    # 验证安装
    if verify_installation; then
        mkdir -p "$(dirname "$INSTALL_FLAG")"
        local ts_version
        ts_version=$(tailscale version 2>/dev/null | head -1)
        cat > "$INSTALL_FLAG" <<EOF
Version: ${ts_version:-unknown}
InstalledAt: $(date '+%Y-%m-%d %H:%M:%S')
EOF

        log_success "$MODULE_NAME 安装完成!"
        show_post_install_info
        return 0
    else
        log_warning "Tailscale 已安装但尚未登录,请运行 'tailscale up' 完成认证"
        mkdir -p "$(dirname "$INSTALL_FLAG")"
        echo "InstalledAt: $(date '+%Y-%m-%d %H:%M:%S')" > "$INSTALL_FLAG"
        show_post_install_info
        return 0
    fi
}

# ============ 卸载函数 ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    if ! ask_yes_no "确定要卸载 Tailscale 吗?"; then
        log_info "已取消卸载"
        return 0
    fi

    # 断开连接
    tailscale down 2>/dev/null || true

    # 停止服务
    systemctl stop tailscaled 2>/dev/null || true
    systemctl disable tailscaled 2>/dev/null || true

    # 卸载软件包
    if command -v apt-get &>/dev/null; then
        apt-get purge -y tailscale 2>/dev/null || true
        apt-get autoremove -y
    fi

    # 清理残留
    rm -rf /var/lib/tailscale
    rm -f /etc/apt/sources.list.d/tailscale.list
    rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg

    rm -f "$INSTALL_FLAG"
    log_success "$MODULE_NAME 已卸载"
}

# ============ 状态检查 ============
status() {
    if check_installed; then
        local version
        version=$(tailscale version 2>/dev/null | head -1)
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"
        echo "  版本: ${version:-未知}"

        if systemctl is-active tailscaled >/dev/null 2>&1; then
            echo -e "  服务: ${GREEN}运行中${NC}"
        else
            echo -e "  服务: ${RED}已停止${NC}"
        fi

        # 显示连接状态
        local ts_status
        ts_status=$(tailscale status --json 2>/dev/null | grep -oP '"BackendState":"\K[^"]+' 2>/dev/null)
        case "$ts_status" in
            Running)
                local ts_ip
                ts_ip=$(tailscale ip -4 2>/dev/null)
                echo -e "  状态: ${GREEN}已连接${NC}"
                echo "  Tailscale IP: ${ts_ip:-未知}"
                ;;
            NeedsLogin)
                echo -e "  状态: ${YELLOW}需要登录${NC}"
                ;;
            Stopped)
                echo -e "  状态: ${RED}已断开${NC}"
                ;;
            *)
                echo -e "  状态: ${YELLOW}${ts_status:-未知}${NC}"
                ;;
        esac
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 验证安装 ============
verify_installation() {
    if ! command -v tailscale &>/dev/null; then
        log_error "tailscale 命令不存在"
        return 1
    fi

    if ! systemctl is-active tailscaled >/dev/null 2>&1; then
        log_error "tailscaled 服务未运行"
        return 1
    fi

    # 检查是否已连接
    local ts_status
    ts_status=$(tailscale status --json 2>/dev/null | grep -oP '"BackendState":"\K[^"]+' 2>/dev/null)
    if [ "$ts_status" = "Running" ]; then
        return 0
    fi

    return 1
}

# ============ 安装后信息 ============
show_post_install_info() {
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null)

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Tailscale 安装完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}管理命令:${NC}
  ${CYAN}tailscale status${NC}           # 查看连接状态
  ${CYAN}tailscale up${NC}               # 连接/登录
  ${CYAN}tailscale down${NC}             # 断开连接
  ${CYAN}tailscale ip${NC}               # 查看Tailscale IP
  ${CYAN}tailscale ping <主机名>${NC}    # 测试连通性

EOF

    if [ -n "$ts_ip" ]; then
        echo -e "${BOLD}Tailscale IP:${NC} ${GREEN}$ts_ip${NC}"
        echo
    fi

    cat << EOF
${BOLD}常用功能:${NC}
  # 作为出口节点 (让其他设备通过此VPS上网)
  tailscale up --advertise-exit-node

  # 子网路由 (暴露局域网给Tailscale网络)
  tailscale up --advertise-routes=192.168.1.0/24

${YELLOW}${BOLD}提示:${NC}
  请在 https://login.tailscale.com/admin 管理设备
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
