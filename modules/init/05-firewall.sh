#!/bin/bash
# modules/init/05-firewall.sh
# 配置UFW防火墙
#
# 功能:
# - 配置UFW基础规则
# - 允许SSH端口
# - 默认拒绝入站,允许出站
# - 安全确认机制防止锁定

# ============ 模块元数据 ============
MODULE_NAME="防火墙"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="init"
MODULE_DESC="配置UFW防火墙基础规则"

# ============ 全局变量 ============
FLAG_FILE="/var/log/vps-tools/init-05-firewall.flag"
CONFIGURED_SSH_PORT=""
ALLOWED_PORTS=()

# ============ 检查函数 (必需) ============
check_installed() {
    # 检查UFW是否已配置
    if command -v ufw >/dev/null 2>&1 && [ -f "$FLAG_FILE" ]; then
        return 0
    fi
    return 1
}

# ============ 安装函数 (必需) ============
install() {
    log_info "开始配置防火墙..."

    # 检查是否已配置
    if check_installed; then
        log_warning "防火墙已配置"
        if ! ask_yes_no "是否重新配置?"; then
            return 0
        fi
    fi

    # 步骤1: 检测SSH端口
    log_step 1 6 "检测SSH端口"
    if ! detect_ssh_port; then
        log_warning "无法自动检测SSH端口,使用默认值22"
        CONFIGURED_SSH_PORT=22
    fi
    log_success "SSH端口: $CONFIGURED_SSH_PORT"

    # 步骤2: 安装UFW
    log_step 2 6 "安装UFW"
    if ! install_ufw; then
        return 1
    fi

    # 步骤3: 检测已安装服务的端口
    log_step 3 6 "检测服务端口"
    detect_service_ports
    if [ ${#ALLOWED_PORTS[@]} -gt 0 ]; then
        log_info "检测到服务端口: ${ALLOWED_PORTS[*]}"
    fi

    # 步骤4: 安全确认
    log_step 4 6 "安全确认"
    show_firewall_warning
    if ! confirm_firewall_setup; then
        log_info "已取消防火墙配置"
        return 0
    fi

    # 步骤5: 配置规则
    log_step 5 6 "配置防火墙规则"
    if ! configure_firewall; then
        return 1
    fi

    # 步骤6: 启用防火墙
    log_step 6 6 "启用防火墙"
    if ! enable_firewall; then
        return 1
    fi

    # 验证安装
    if verify_installation; then
        # 创建标记文件
        mkdir -p "$(dirname "$FLAG_FILE")"
        cat > "$FLAG_FILE" << EOF
SSHPort: $CONFIGURED_SSH_PORT
AllowedPorts: ${ALLOWED_PORTS[*]}
ConfiguredAt: $(date '+%Y-%m-%d %H:%M:%S')
EOF

        log_success "$MODULE_NAME 配置完成!"
        show_post_install_info
        return 0
    else
        log_error "验证失败"
        return 1
    fi
}

# ============ 检测SSH端口 ============
detect_ssh_port() {
    local ssh_flag="/var/log/vps-tools/init-03-ssh-config.flag"

    # 从SSH配置模块获取端口
    if [ -f "$ssh_flag" ]; then
        CONFIGURED_SSH_PORT=$(grep "^Port:" "$ssh_flag" | cut -d: -f2 | tr -d ' ')
        if [ -n "$CONFIGURED_SSH_PORT" ]; then
            return 0
        fi
    fi

    # 从sshd_config读取
    local port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -n "$port" ]; then
        CONFIGURED_SSH_PORT="$port"
        return 0
    fi

    # 从当前连接检测
    local port=$(netstat -tuln 2>/dev/null | grep 'LISTEN' | grep ':22 ' | awk '{print $4}' | cut -d: -f2 | head -1)
    if [ -n "$port" ]; then
        CONFIGURED_SSH_PORT="$port"
        return 0
    fi

    return 1
}

# ============ 检测服务端口 ============
detect_service_ports() {
    ALLOWED_PORTS=()

    # 检测Docker相关端口 (Nginx Proxy Manager)
    local npm_flag="/var/log/vps-tools/install-nginx-proxy-manager.flag"
    if [ -f "$npm_flag" ]; then
        ALLOWED_PORTS+=("80/tcp" "443/tcp" "81/tcp")
        log_info "检测到Nginx Proxy Manager端口: 80, 443, 81"
    fi

    # 检测3x-ui
    local xui_flag="/var/log/vps-tools/install-3x-ui.flag"
    if [ -f "$xui_flag" ]; then
        # 3x-ui的端口需要用户配置,这里仅提示
        log_info "检测到3x-ui,请手动配置相关端口"
    fi
}

# ============ 安装UFW ============
install_ufw() {
    if command -v ufw >/dev/null 2>&1; then
        log_info "UFW已安装"
        return 0
    fi

    log_info "正在安装UFW..."

    # 更新包索引
    if ! apt-get update -qq; then
        log_error "更新包索引失败"
        return 1
    fi

    # 安装ufw
    if ! apt-get install -y ufw; then
        log_error "安装UFW失败"
        return 1
    fi

    log_success "UFW安装成功"
    return 0
}

# ============ 显示警告 ============
show_firewall_warning() {
    cat << EOF

${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${RED}${BOLD}                    ⚠️  警告 ⚠️                        ${NC}
${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${YELLOW}即将启用防火墙,这可能会${RED}${BOLD}中断当前连接${NC}${YELLOW}!${NC}

${BOLD}将要应用的规则:${NC}
  - 默认策略: ${RED}拒绝所有入站${NC}, ${GREEN}允许所有出站${NC}
  - 允许SSH: ${GREEN}$CONFIGURED_SSH_PORT/tcp${NC}

EOF

    if [ ${#ALLOWED_PORTS[@]} -gt 0 ]; then
        echo -e "${BOLD}检测到的服务端口:${NC}"
        for port in "${ALLOWED_PORTS[@]}"; do
            echo -e "  - 允许: ${GREEN}$port${NC}"
        done
        echo
    fi

    cat << EOF
${RED}${BOLD}请确保:${NC}
  1. SSH端口 ${GREEN}$CONFIGURED_SSH_PORT${NC} 是正确的
  2. 你可以通过这个端口访问服务器
  3. ${RED}${BOLD}不要关闭当前SSH会话${NC}

${YELLOW}如果配置错误,你将${RED}${BOLD}失去服务器访问权限${NC}${YELLOW}!${NC}

${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF
}

# ============ 确认配置 ============
confirm_firewall_setup() {
    local confirm
    printf "${RED}${BOLD}请输入 'yes' 确认继续: ${NC}"
    read -r confirm

    if [ "$confirm" = "yes" ]; then
        return 0
    else
        return 1
    fi
}

# ============ 配置防火墙 ============
configure_firewall() {
    log_info "正在配置防火墙规则..."

    # 重置防火墙 (清除所有规则)
    if ! ufw --force reset >/dev/null 2>&1; then
        log_error "重置防火墙失败"
        return 1
    fi
    log_info "已重置防火墙规则"

    # 设置默认策略
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    log_success "已设置默认策略"

    # 允许SSH
    if ! ufw allow "$CONFIGURED_SSH_PORT/tcp" comment 'SSH' >/dev/null 2>&1; then
        log_error "添加SSH规则失败"
        return 1
    fi
    log_success "已允许SSH端口 $CONFIGURED_SSH_PORT"

    # 允许检测到的服务端口
    for port in "${ALLOWED_PORTS[@]}"; do
        local port_num=$(echo "$port" | cut -d/ -f1)
        local proto=$(echo "$port" | cut -d/ -f2)

        local comment=""
        case "$port_num" in
            80) comment="HTTP" ;;
            443) comment="HTTPS" ;;
            81) comment="NPM-Admin" ;;
            *) comment="Service-$port_num" ;;
        esac

        if ! ufw allow "$port" comment "$comment" >/dev/null 2>&1; then
            log_warning "添加规则 $port 失败"
        else
            log_success "已允许端口 $port ($comment)"
        fi
    done

    return 0
}

# ============ 启用防火墙 ============
enable_firewall() {
    log_info "正在启用防火墙..."

    # 启用UFW
    if ! ufw --force enable >/dev/null 2>&1; then
        log_error "启用防火墙失败"
        return 1
    fi

    # 等待防火墙生效
    sleep 2

    log_success "防火墙已启用"
    return 0
}

# ============ 卸载函数 (可选) ============
uninstall() {
    log_warning "此操作将禁用防火墙"

    if ! check_installed; then
        log_warning "防火墙未配置"
        return 0
    fi

    # 确认卸载
    if ! ask_yes_no "确定要禁用防火墙吗?"; then
        log_info "已取消"
        return 0
    fi

    # 禁用UFW
    ufw --force disable

    # 删除标记
    rm -f "$FLAG_FILE"

    log_success "防火墙已禁用"
    return 0
}

# ============ 状态检查 (可选) ============
status() {
    if check_installed; then
        printf "${GREEN}✓${NC} %s: 已配置\n" "$MODULE_NAME"

        # 检查UFW状态
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            printf "  状态: ${GREEN}已启用${NC}\n"
        else
            printf "  状态: ${RED}已禁用${NC}\n"
        fi

        # 显示配置信息
        if [ -f "$FLAG_FILE" ]; then
            local ssh_port=$(grep "^SSHPort:" "$FLAG_FILE" | cut -d: -f2 | tr -d ' ')
            local allowed_ports=$(grep "^AllowedPorts:" "$FLAG_FILE" | cut -d: -f2-)
            local configured_at=$(grep "^ConfiguredAt:" "$FLAG_FILE" | cut -d: -f2- | tr -d ' ')

            printf "  SSH端口: %s\n" "${ssh_port:-未知}"
            if [ -n "$allowed_ports" ]; then
                printf "  允许端口: %s\n" "$allowed_ports"
            fi
            printf "  配置时间: %s\n" "${configured_at:-未知}"
        fi

        # 显示规则摘要
        printf "\n  ${BOLD}防火墙规则摘要:${NC}\n"
        ufw status numbered 2>/dev/null | grep -v "^Status:" | head -10 | sed 's/^/    /'
    else
        printf "${RED}✗${NC} %s: 未配置\n" "$MODULE_NAME"
    fi
}

# ============ 验证安装 (内部函数) ============
verify_installation() {
    # 验证UFW已安装
    if ! command -v ufw >/dev/null 2>&1; then
        log_error "UFW未安装"
        return 1
    fi

    # 验证UFW已启用
    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        log_error "UFW未启用"
        return 1
    fi

    # 验证SSH规则存在
    if ! ufw status 2>/dev/null | grep -q "$CONFIGURED_SSH_PORT/tcp"; then
        log_error "SSH规则不存在"
        return 1
    fi

    return 0
}

# ============ 安装后信息 (可选) ============
show_post_install_info() {
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}防火墙配置完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}配置信息:${NC}
  状态: ${GREEN}已启用${NC}
  SSH端口: ${GREEN}$CONFIGURED_SSH_PORT/tcp${NC}
  默认策略: 拒绝入站 / 允许出站

EOF

    if [ ${#ALLOWED_PORTS[@]} -gt 0 ]; then
        echo -e "${BOLD}允许的服务端口:${NC}"
        for port in "${ALLOWED_PORTS[@]}"; do
            echo -e "  - ${GREEN}$port${NC}"
        done
        echo
    fi

    cat << EOF
${BOLD}管理命令:${NC}
  查看状态: sudo ufw status verbose
  查看规则: sudo ufw status numbered
  允许端口: sudo ufw allow <port>/tcp
  删除规则: sudo ufw delete <规则编号>
  禁用防火墙: sudo ufw disable

${YELLOW}${BOLD}重要提示:${NC}
  1. ${GREEN}当前SSH连接应该正常${NC}
  2. 如需开放其他端口,使用: sudo ufw allow <port>/tcp
  3. Fail2Ban规则会自动添加到iptables

${BOLD}测试连接:${NC}
  请在新终端测试SSH连接,确认可以正常登录

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
