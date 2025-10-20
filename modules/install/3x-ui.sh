#!/bin/bash
# modules/install/3x-ui.sh
# 3x-ui 安装模块

# ============ 模块元数据 ============
MODULE_NAME="3x-ui"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="install"
MODULE_DESC="安装 3x-ui 面板"

# ============ 全局变量 ============
UI_FLAG="/usr/local/x-ui/installed.flag"

# ============ 检查函数 ============
check_installed() {
    command -v x-ui &>/dev/null || [ -f "$UI_FLAG" ]
}

check_dependencies() {
    return 0
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    if check_installed; then
        log_warning "3x-ui 已安装"
        if ! ask_yes_no "是否重新安装?"; then
            return 0
        fi
    fi

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    log_step 1 4 "下载安装脚本"
    local install_script="/tmp/3xui_install.sh"

    if ! wget --no-check-certificate -O "$install_script" \
        https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh; then
        log_error "下载安装脚本失败"
        return 1
    fi

    log_step 2 4 "设置执行权限"
    chmod +x "$install_script"

    log_step 3 4 "执行安装脚本"
    log_warning "安装过程需要交互,请按提示操作"
    echo

    if ! bash "$install_script"; then
        log_error "安装失败"
        rm -f "$install_script"
        return 1
    fi

    log_step 4 4 "清理临时文件"
    rm -f "$install_script"

    # 创建标记
    mkdir -p "$(dirname "$UI_FLAG")"
    touch "$UI_FLAG"

    log_success "$MODULE_NAME 安装完成!"
    show_post_install_info

    return 0
}

# ============ 卸载函数 ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "3x-ui 未安装"
        return 0
    fi

    if command -v x-ui &>/dev/null; then
        log_info "使用官方卸载方法..."
        x-ui uninstall
    else
        log_warning "找不到 x-ui 命令,手动清理..."
        rm -rf /usr/local/x-ui
        systemctl stop x-ui 2>/dev/null || true
        systemctl disable x-ui 2>/dev/null || true
    fi

    rm -f "$UI_FLAG"
    log_success "3x-ui 卸载完成"
}

# ============ 状态检查 ============
status() {
    if check_installed; then
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"

        if systemctl is-active --quiet x-ui; then
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
    local ip=$(get_server_ip)

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}3x-ui 安装完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}管理命令:${NC}
  ${CYAN}x-ui${NC}                    # 打开管理菜单
  ${CYAN}x-ui start${NC}              # 启动面板
  ${CYAN}x-ui stop${NC}               # 停止面板
  ${CYAN}x-ui restart${NC}            # 重启面板
  ${CYAN}x-ui status${NC}             # 查看状态

${YELLOW}${BOLD}提示:${NC}
  请使用 'x-ui' 命令查看面板访问地址和凭据

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
