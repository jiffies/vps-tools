#!/bin/bash
# modules/init/04-fail2ban.sh
# 配置Fail2Ban防暴力破解
#
# 功能:
# - 安装fail2ban
# - 配置SSH保护
# - 设置封禁规则 (bantime, maxretry等)
# - 启动并启用服务

# ============ 模块元数据 ============
MODULE_NAME="Fail2Ban"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="init"
MODULE_DESC="配置Fail2Ban防止SSH暴力破解"

# ============ 全局变量 ============
FLAG_FILE="/var/log/vps-tools/init-04-fail2ban.flag"
FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"
FAIL2BAN_CONFIG_BACKUP="/etc/fail2ban/jail.local.backup.$(date +%Y%m%d_%H%M%S)"
CONFIGURED_SSH_PORT=""

# ============ 检查函数 (必需) ============
check_installed() {
    # 检查fail2ban是否安装并配置
    if command -v fail2ban-client >/dev/null 2>&1 && [ -f "$FLAG_FILE" ]; then
        return 0
    fi
    return 1
}

# ============ 安装函数 (必需) ============
install() {
    log_info "开始配置Fail2Ban..."

    # 检查是否已安装
    if check_installed; then
        log_warning "Fail2Ban已配置"
        if ! ask_yes_no "是否重新配置?"; then
            return 0
        fi
    fi

    # 步骤1: 检测SSH端口
    log_step 1 5 "检测SSH配置"
    if ! detect_ssh_port; then
        log_warning "无法自动检测SSH端口,使用默认值22"
        CONFIGURED_SSH_PORT=22
    fi
    log_success "SSH端口: $CONFIGURED_SSH_PORT"

    # 步骤2: 安装fail2ban
    log_step 2 5 "安装Fail2Ban"
    if ! install_fail2ban; then
        return 1
    fi

    # 步骤3: 备份现有配置
    log_step 3 5 "备份配置"
    if [ -f "$FAIL2BAN_CONFIG" ]; then
        cp "$FAIL2BAN_CONFIG" "$FAIL2BAN_CONFIG_BACKUP"
        log_success "已备份: $FAIL2BAN_CONFIG_BACKUP"
    fi

    # 步骤4: 配置jail.local
    log_step 4 5 "配置Fail2Ban规则"
    if ! configure_fail2ban; then
        return 1
    fi

    # 步骤5: 启动服务
    log_step 5 5 "启动Fail2Ban服务"
    if ! start_fail2ban_service; then
        return 1
    fi

    # 验证安装
    if verify_installation; then
        # 创建标记文件
        mkdir -p "$(dirname "$FLAG_FILE")"
        cat > "$FLAG_FILE" << EOF
SSHPort: $CONFIGURED_SSH_PORT
ConfiguredAt: $(date '+%Y-%m-%d %H:%M:%S')
ConfigBackup: $FAIL2BAN_CONFIG_BACKUP
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
    local port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    if [ -n "$port" ]; then
        CONFIGURED_SSH_PORT="$port"
        return 0
    fi

    # 从netstat检测
    local port=$(netstat -tuln 2>/dev/null | grep 'LISTEN' | grep ':22 ' | awk '{print $4}' | cut -d: -f2)
    if [ -n "$port" ]; then
        CONFIGURED_SSH_PORT="$port"
        return 0
    fi

    return 1
}

# ============ 安装fail2ban ============
install_fail2ban() {
    if command -v fail2ban-client >/dev/null 2>&1; then
        log_info "Fail2Ban已安装"
        return 0
    fi

    log_info "正在安装Fail2Ban..."

    # 更新包索引
    if ! apt-get update -qq; then
        log_error "更新包索引失败"
        return 1
    fi

    # 安装fail2ban
    if ! apt-get install -y fail2ban; then
        log_error "安装Fail2Ban失败"
        return 1
    fi

    log_success "Fail2Ban安装成功"
    return 0
}

# ============ 配置Fail2Ban ============
configure_fail2ban() {
    cat > "$FAIL2BAN_CONFIG" <<EOF
# VPS Tools 自动生成的Fail2Ban配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

[DEFAULT]
# 封禁时间 (秒)
bantime = 3600

# 统计时间窗口 (秒)
findtime = 600

# 最大重试次数
maxretry = 5

# 忽略的IP (本地和私有IP)
ignoreip = 127.0.0.1/8 ::1

# 封禁动作 (使用iptables)
banaction = iptables-multiport
banaction_allports = iptables-allports

# 邮件通知 (需要配置sendmail)
# destemail = admin@example.com
# sendername = Fail2Ban
# action = %(action_mwl)s

[sshd]
# SSH防护
enabled = true
port = $CONFIGURED_SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

# 更严格的重试限制
# 3次失败尝试,封禁1小时

[sshd-ddos]
# SSH DDOS防护
enabled = true
port = $CONFIGURED_SSH_PORT
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 2
bantime = 7200

EOF

    log_success "Fail2Ban配置已生成"
    return 0
}

# ============ 启动服务 ============
start_fail2ban_service() {
    # 重启fail2ban
    if ! systemctl restart fail2ban; then
        log_error "重启Fail2Ban失败"
        return 1
    fi

    # 启用开机自启
    if ! systemctl enable fail2ban >/dev/null 2>&1; then
        log_warning "设置开机自启失败"
    fi

    # 等待服务启动
    sleep 2

    # 检查服务状态
    if ! systemctl is-active fail2ban >/dev/null 2>&1; then
        log_error "Fail2Ban服务未运行"
        return 1
    fi

    log_success "Fail2Ban服务已启动"
    return 0
}

# ============ 卸载函数 (可选) ============
uninstall() {
    log_info "开始卸载Fail2Ban..."

    if ! check_installed; then
        log_warning "Fail2Ban未安装"
        return 0
    fi

    # 确认卸载
    if ! ask_yes_no "确定要卸载Fail2Ban吗?"; then
        log_info "已取消卸载"
        return 0
    fi

    # 停止服务
    systemctl stop fail2ban
    systemctl disable fail2ban

    # 询问是否保留配置
    local keep_config=false
    if ask_yes_no "是否保留配置文件?"; then
        keep_config=true
    fi

    # 卸载软件包
    if [ "$keep_config" = true ]; then
        apt-get remove -y fail2ban
    else
        apt-get purge -y fail2ban
    fi

    # 删除标记
    rm -f "$FLAG_FILE"

    log_success "Fail2Ban已卸载"
    return 0
}

# ============ 状态检查 (可选) ============
status() {
    if check_installed; then
        printf "${GREEN}✓${NC} %s: 已安装\n" "$MODULE_NAME"

        # 检查服务状态
        if systemctl is-active fail2ban >/dev/null 2>&1; then
            printf "  服务状态: ${GREEN}运行中${NC}\n"
        else
            printf "  服务状态: ${RED}已停止${NC}\n"
        fi

        # 显示jail状态
        if command -v fail2ban-client >/dev/null 2>&1; then
            local sshd_status=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $NF}')
            if [ -n "$sshd_status" ]; then
                printf "  当前封禁IP数: ${YELLOW}%s${NC}\n" "$sshd_status"
            fi
        fi

        # 显示配置信息
        if [ -f "$FLAG_FILE" ]; then
            local ssh_port=$(grep "^SSHPort:" "$FLAG_FILE" | cut -d: -f2 | tr -d ' ')
            local configured_at=$(grep "^ConfiguredAt:" "$FLAG_FILE" | cut -d: -f2- | tr -d ' ')

            printf "  SSH端口: %s\n" "${ssh_port:-未知}"
            printf "  配置时间: %s\n" "${configured_at:-未知}"
        fi
    else
        printf "${RED}✗${NC} %s: 未安装\n" "$MODULE_NAME"
    fi
}

# ============ 验证安装 (内部函数) ============
verify_installation() {
    # 验证fail2ban已安装
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_error "Fail2Ban未安装"
        return 1
    fi

    # 验证服务运行
    if ! systemctl is-active fail2ban >/dev/null 2>&1; then
        log_error "Fail2Ban服务未运行"
        return 1
    fi

    # 验证sshd jail已启用
    if ! fail2ban-client status sshd >/dev/null 2>&1; then
        log_error "SSH jail未启用"
        return 1
    fi

    return 0
}

# ============ 安装后信息 (可选) ============
show_post_install_info() {
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Fail2Ban配置完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}配置信息:${NC}
  SSH端口: ${GREEN}$CONFIGURED_SSH_PORT${NC}
  封禁时间: ${GREEN}3600秒 (1小时)${NC}
  最大重试: ${GREEN}3次${NC}
  统计窗口: ${GREEN}600秒 (10分钟)${NC}

${BOLD}管理命令:${NC}
  查看状态: fail2ban-client status
  查看SSH jail: fail2ban-client status sshd
  查看封禁IP: fail2ban-client status sshd | grep "Banned IP"
  解封IP: fail2ban-client set sshd unbanip <IP>

${BOLD}配置文件:${NC}
  主配置: /etc/fail2ban/jail.local
  日志: /var/log/fail2ban.log

${YELLOW}${BOLD}注意:${NC}
  - Fail2Ban会自动保护SSH端口 $CONFIGURED_SSH_PORT
  - 3次失败登录尝试将被封禁1小时
  - 请确保防火墙配置正确,以便Fail2Ban规则生效

${BOLD}下一步:${NC}
  建议配置防火墙 (选项6)

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
