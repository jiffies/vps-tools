#!/bin/bash
# modules/{category}/{module-name}.sh
# {模块描述}
#
# 使用方法:
# 1. 复制此模板
# 2. 重命名文件
# 3. 修改元数据
# 4. 实现必需函数: check_installed, install
# 5. 实现可选函数: uninstall, status, check_dependencies

# ============ 模块元数据 ============
MODULE_NAME="示例模块"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""  # 依赖的其他模块,空格分隔,如: "docker nginx"
MODULE_CATEGORY="install"  # init/install/manage
MODULE_DESC="这是一个示例模块"

# ============ 全局变量 ============
INSTALL_DIR="/opt/example"
INSTALL_FLAG="$INSTALL_DIR/installed.flag"

# ============ 检查函数 (必需) ============
check_installed() {
    # 检查模块是否已安装
    # 返回 0 表示已安装, 1 表示未安装

    [ -f "$INSTALL_FLAG" ]
    return $?
}

# ============ 依赖检查 (可选) ============
check_dependencies() {
    # 检查依赖是否满足
    # 如果有 MODULE_DEPS, module-loader 会自动处理
    # 这里可以添加额外的检查逻辑

    return 0
}

# ============ 安装函数 (必需) ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    # 检查是否已安装
    if check_installed; then
        log_warning "$MODULE_NAME 已安装"
        if ! ask_yes_no "是否重新安装?"; then
            return 0
        fi
    fi

    # 步骤1: 示例步骤
    log_step 1 5 "执行步骤1"
    # 你的安装逻辑...

    # 步骤2
    log_step 2 5 "执行步骤2"
    # ...

    # 步骤3
    log_step 3 5 "执行步骤3"
    # ...

    # 步骤4
    log_step 4 5 "执行步骤4"
    # ...

    # 步骤5: 验证安装
    log_step 5 5 "验证安装"
    if verify_installation; then
        # 创建安装标记
        mkdir -p "$(dirname "$INSTALL_FLAG")"
        touch "$INSTALL_FLAG"
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$INSTALL_FLAG"

        log_success "$MODULE_NAME 安装成功!"
        show_post_install_info
        return 0
    else
        log_error "$MODULE_NAME 安装失败"
        return 1
    fi
}

# ============ 卸载函数 (可选) ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    # 确认卸载
    if ! ask_yes_no "确定要卸载 $MODULE_NAME 吗?"; then
        log_info "已取消卸载"
        return 0
    fi

    # 询问是否保留数据
    local keep_data=false
    if ask_yes_no "是否保留数据?"; then
        keep_data=true
    fi

    # 停止服务 (如果有)
    # systemctl stop example

    # 删除文件
    if [ "$keep_data" = true ]; then
        local backup_dir="$INSTALL_DIR.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$INSTALL_DIR" "$backup_dir"
        log_info "数据已备份到: $backup_dir"
    else
        rm -rf "$INSTALL_DIR"
        log_info "数据已删除"
    fi

    # 删除标记
    rm -f "$INSTALL_FLAG"

    log_success "$MODULE_NAME 卸载完成"
    return 0
}

# ============ 状态检查 (可选) ============
status() {
    if check_installed; then
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"

        # 显示详细状态
        if systemctl is-active --quiet example; then
            echo -e "  状态: ${GREEN}运行中${NC}"
        else
            echo -e "  状态: ${RED}已停止${NC}"
        fi

        # 显示其他信息
        echo "  安装目录: $INSTALL_DIR"
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 验证安装 (内部函数) ============
verify_installation() {
    # 验证安装是否成功
    # 例如: 检查文件是否存在, 服务是否运行等

    if [ -d "$INSTALL_DIR" ]; then
        return 0
    fi

    return 1
}

# ============ 安装后信息 (可选) ============
show_post_install_info() {
    local ip=$(get_server_ip)

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}$MODULE_NAME 安装完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}访问信息:${NC}
  地址: http://$ip:8080

${BOLD}默认凭据:${NC}
  用户名: admin
  密码: changeme

${YELLOW}${BOLD}重要提示:${NC}
  1. 请修改默认密码
  2. 配置防火墙规则

${BOLD}管理命令:${NC}
  启动: systemctl start example
  停止: systemctl stop example
  状态: systemctl status example

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# ============ 模块独立运行支持 (必需) ============
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    # 当直接执行此脚本时
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    source "$SCRIPT_DIR/lib/common.sh"

    case "${1:-install}" in
        install)
            install
            ;;
        uninstall)
            uninstall
            ;;
        status)
            status
            ;;
        *)
            echo "用法: $0 {install|uninstall|status}"
            exit 1
            ;;
    esac
fi
