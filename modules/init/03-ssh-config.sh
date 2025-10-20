#!/bin/bash
# modules/init/03-ssh-config.sh
# SSH安全配置
#
# 功能:
# - 配置SSH密钥认证
# - 禁用root登录
# - 禁用密码认证
# - 自定义SSH端口
# - 配置SSH socket (如果存在)
# - 自动备份和回滚机制

# ============ 模块元数据 ============
MODULE_NAME="SSH安全配置"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="init"
MODULE_DESC="配置SSH密钥认证并加固SSH安全"

# ============ 全局变量 ============
FLAG_FILE="/var/log/vps-tools/init-03-ssh-config.flag"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
SSH_SOCKET="/usr/lib/systemd/system/ssh.socket"
SSH_SOCKET_BACKUP=""
CONFIGURED_PORT=""
CONFIGURED_USER=""

# ============ 检查函数 (必需) ============
check_installed() {
    [ -f "$FLAG_FILE" ]
    return $?
}

# ============ 安装函数 (必需) ============
install() {
    log_info "开始配置SSH安全..."

    # 检查是否已配置
    if check_installed; then
        log_warning "SSH已配置过"
        if [ -f "$FLAG_FILE" ]; then
            CONFIGURED_PORT=$(grep "^Port:" "$FLAG_FILE" | cut -d: -f2 | tr -d ' ')
            CONFIGURED_USER=$(grep "^User:" "$FLAG_FILE" | cut -d: -f2 | tr -d ' ')
            log_info "当前配置 - 端口: $CONFIGURED_PORT, 用户: $CONFIGURED_USER"
        fi
        if ! ask_yes_no "是否重新配置?"; then
            return 0
        fi
    fi

    # 步骤1: 选择用户
    log_step 1 8 "选择SSH登录用户"
    local username
    if ! select_user; then
        return 1
    fi
    CONFIGURED_USER="$username"
    log_success "已选择用户: $username"

    # 步骤2: 设置SSH端口
    log_step 2 8 "设置SSH端口"
    local ssh_port
    printf "${BLUE}请输入SSH端口 [默认22]: ${NC}"
    read -r ssh_port
    ssh_port=${ssh_port:-22}

    # 验证端口号
    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ]; then
        log_error "无效的端口号: $ssh_port"
        return 1
    fi
    CONFIGURED_PORT="$ssh_port"
    log_success "SSH端口: $ssh_port"

    # 步骤3: 准备SSH密钥目录
    log_step 3 8 "准备SSH密钥目录"
    if ! prepare_ssh_directory; then
        return 1
    fi

    # 步骤4: 引导用户配置SSH密钥
    log_step 4 8 "SSH密钥配置指导"
    show_ssh_key_guide

    # 等待用户上传公钥
    log_info "等待公钥上传..."
    local ssh_dir="/home/$username/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"

    while true; do
        printf "${BLUE}是否已完成公钥上传? [y/N]: ${NC}"
        read -r key_uploaded

        if [[ "$key_uploaded" == "y" || "$key_uploaded" == "Y" ]]; then
            if [ -f "$authorized_keys" ] && [ -s "$authorized_keys" ]; then
                log_success "已确认公钥上传成功!"
                break
            else
                log_error "未检测到authorized_keys文件或文件为空"
                log_info "请确保正确上传公钥后重试"
            fi
        else
            log_info "请先完成公钥上传"
        fi
    done

    # 步骤5: 备份配置文件
    log_step 5 8 "备份SSH配置"
    if ! backup_ssh_config; then
        return 1
    fi

    # 步骤6: 修改SSH配置
    log_step 6 8 "修改SSH配置"
    if ! configure_ssh; then
        return 1
    fi

    # 步骤7: 测试配置
    log_step 7 8 "测试SSH配置"
    if ! test_ssh_config; then
        log_error "SSH配置测试失败,正在回滚..."
        rollback_ssh_config
        return 1
    fi

    # 步骤8: 重启SSH服务
    log_step 8 8 "重启SSH服务"
    if ! restart_ssh_service; then
        log_error "SSH服务重启失败,正在回滚..."
        rollback_ssh_config
        return 1
    fi

    # 验证服务状态
    if verify_installation; then
        # 创建标记文件
        mkdir -p "$(dirname "$FLAG_FILE")"
        cat > "$FLAG_FILE" << EOF
Port: $CONFIGURED_PORT
User: $CONFIGURED_USER
ConfiguredAt: $(date '+%Y-%m-%d %H:%M:%S')
BackupFile: $SSH_CONFIG_BACKUP
EOF

        log_success "$MODULE_NAME 完成!"
        show_post_install_info
        return 0
    else
        log_error "验证失败"
        rollback_ssh_config
        return 1
    fi
}

# ============ 选择用户 ============
select_user() {
    # 列出系统中的普通用户 (UID >= 1000)
    local users=($(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd))

    if [ ${#users[@]} -eq 0 ]; then
        log_error "没有找到普通用户"
        log_info "请先创建用户 (选项3: 创建用户)"
        return 1
    fi

    printf "\n${BOLD}可用用户:${NC}\n"
    for i in "${!users[@]}"; do
        printf "  %d. %s\n" "$((i+1))" "${users[$i]}"
    done

    local choice
    while true; do
        printf "\n${BLUE}请选择用户 [1-%d]: ${NC}" "${#users[@]}"
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#users[@]}" ]; then
            username="${users[$((choice-1))]}"
            return 0
        else
            log_error "无效选择"
        fi
    done
}

# ============ 准备SSH目录 ============
prepare_ssh_directory() {
    local ssh_dir="/home/$username/.ssh"

    # 创建.ssh目录
    if [ ! -d "$ssh_dir" ]; then
        if ! mkdir -p "$ssh_dir"; then
            log_error "创建SSH目录失败"
            return 1
        fi
    fi

    # 设置权限
    chmod 700 "$ssh_dir"
    chown "$username:$username" "$ssh_dir"

    log_success "SSH目录已准备: $ssh_dir"
    return 0
}

# ============ SSH密钥配置指导 ============
show_ssh_key_guide() {
    local ip=$(get_server_ip)

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${BOLD}${YELLOW}SSH密钥配置指导${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${BOLD}步骤1: 在本地生成SSH密钥${NC}

${CYAN}Windows用户 (PowerShell):${NC}
  ssh-keygen -t ed25519 -f "\$env:USERPROFILE\\.ssh\\${username}_ed25519" -C "your_email@example.com"

${CYAN}Linux/MacOS用户:${NC}
  ssh-keygen -t ed25519 -f ~/.ssh/${username}_ed25519 -C "your_email@example.com"

${BOLD}步骤2: 上传公钥到服务器${NC}

${CYAN}Windows用户 (PowerShell):${NC}
  scp "\$env:USERPROFILE\\.ssh\\${username}_ed25519.pub" ${username}@${ip}:~/.ssh/authorized_keys

${CYAN}Linux/MacOS用户:${NC}
  ssh-copy-id -i ~/.ssh/${username}_ed25519.pub -p $CONFIGURED_PORT $username@$ip

${YELLOW}${BOLD}注意:${NC}
  - 如果提示输入密码,请输入用户 ${GREEN}$username${NC} 的密码
  - 生成密钥时可以设置密码短语,也可以留空
  - 私钥(${username}_ed25519)请妥善保管,不要泄露

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# ============ 备份SSH配置 ============
backup_ssh_config() {
    # 备份sshd_config
    if ! cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"; then
        log_error "备份SSH配置失败"
        return 1
    fi
    log_success "已备份: $SSH_CONFIG_BACKUP"

    # 备份ssh.socket (如果存在)
    if [ -f "$SSH_SOCKET" ]; then
        SSH_SOCKET_BACKUP="$SSH_SOCKET.backup.$(date +%Y%m%d_%H%M%S)"
        if ! cp "$SSH_SOCKET" "$SSH_SOCKET_BACKUP"; then
            log_warning "备份SSH socket失败"
        else
            log_success "已备份: $SSH_SOCKET_BACKUP"
        fi
    fi

    return 0
}

# ============ 配置SSH ============
configure_ssh() {
    # 生成新的SSH配置
    cat > "$SSH_CONFIG" <<EOF
# VPS Tools 自动生成的SSH配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 备份文件: $SSH_CONFIG_BACKUP

Include /etc/ssh/sshd_config.d/*.conf

# 端口配置
Port $CONFIGURED_PORT

# 认证配置
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# 其他安全设置
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# 日志级别
LogLevel INFO

# 连接设置
ClientAliveInterval 120
ClientAliveCountMax 3
MaxAuthTries 3
MaxSessions 10
EOF

    log_success "SSH配置已生成"

    # 配置ssh.socket (如果存在)
    if [ -f "$SSH_SOCKET" ]; then
        cat > "$SSH_SOCKET" <<EOF
[Unit]
Description=OpenBSD Secure Shell server socket
Before=sockets.target ssh.service
ConditionPathExists=!/etc/ssh/sshd_not_to_be_run

[Socket]
ListenStream=$CONFIGURED_PORT
Accept=no
FreeBind=yes

[Install]
WantedBy=sockets.target
RequiredBy=ssh.service
EOF
        log_success "SSH socket已配置"

        # 重载systemd
        systemctl daemon-reload
    fi

    return 0
}

# ============ 测试SSH配置 ============
test_ssh_config() {
    if /usr/sbin/sshd -t 2>&1; then
        log_success "SSH配置测试通过"
        return 0
    else
        log_error "SSH配置测试失败"
        return 1
    fi
}

# ============ 重启SSH服务 ============
restart_ssh_service() {
    # 重启ssh.socket (如果存在且正在运行)
    if [ -f "$SSH_SOCKET" ] && systemctl is-active ssh.socket >/dev/null 2>&1; then
        if ! systemctl restart ssh.socket; then
            log_error "重启ssh.socket失败"
            return 1
        fi
        log_success "ssh.socket已重启"
    fi

    # 重启SSH服务
    if ! systemctl restart ssh; then
        log_error "重启SSH服务失败"
        return 1
    fi

    # 等待服务启动
    sleep 2

    # 检查服务状态
    if ! systemctl is-active ssh >/dev/null 2>&1; then
        log_error "SSH服务未运行"
        return 1
    fi

    log_success "SSH服务已重启"
    return 0
}

# ============ 回滚配置 ============
rollback_ssh_config() {
    log_warning "正在回滚SSH配置..."

    # 恢复sshd_config
    if [ -f "$SSH_CONFIG_BACKUP" ]; then
        cp "$SSH_CONFIG_BACKUP" "$SSH_CONFIG"
        log_info "已恢复sshd_config"
    fi

    # 恢复ssh.socket
    if [ -n "$SSH_SOCKET_BACKUP" ] && [ -f "$SSH_SOCKET_BACKUP" ]; then
        cp "$SSH_SOCKET_BACKUP" "$SSH_SOCKET"
        log_info "已恢复ssh.socket"
        systemctl daemon-reload
    fi

    # 重启服务
    systemctl restart ssh
    if [ -f "$SSH_SOCKET" ]; then
        systemctl restart ssh.socket 2>/dev/null
    fi

    log_success "配置已回滚"
}

# ============ 卸载函数 (可选) ============
uninstall() {
    log_warning "此模块不支持自动卸载"
    log_info "如需恢复SSH配置,请手动编辑 $SSH_CONFIG"

    if [ -f "$FLAG_FILE" ]; then
        local backup=$(grep "^BackupFile:" "$FLAG_FILE" | cut -d: -f2- | tr -d ' ')
        if [ -n "$backup" ] && [ -f "$backup" ]; then
            log_info "可以从备份恢复: $backup"
            if ask_yes_no "是否从备份恢复?"; then
                cp "$backup" "$SSH_CONFIG"
                systemctl restart ssh
                log_success "已从备份恢复"
                rm -f "$FLAG_FILE"
                return 0
            fi
        fi
    fi

    return 1
}

# ============ 状态检查 (可选) ============
status() {
    if check_installed; then
        printf "${GREEN}✓${NC} %s: 已配置\n" "$MODULE_NAME"

        if [ -f "$FLAG_FILE" ]; then
            local port=$(grep "^Port:" "$FLAG_FILE" | cut -d: -f2 | tr -d ' ')
            local user=$(grep "^User:" "$FLAG_FILE" | cut -d: -f2 | tr -d ' ')
            local configured_at=$(grep "^ConfiguredAt:" "$FLAG_FILE" | cut -d: -f2- | tr -d ' ')

            printf "  端口: %s\n" "${port:-未知}"
            printf "  用户: %s\n" "${user:-未知}"
            printf "  配置时间: %s\n" "${configured_at:-未知}"

            # 检查SSH服务状态
            if systemctl is-active ssh >/dev/null 2>&1; then
                printf "  SSH服务: ${GREEN}运行中${NC}\n"
            else
                printf "  SSH服务: ${RED}已停止${NC}\n"
            fi

            # 检查端口监听
            if [ -n "$port" ] && netstat -tuln 2>/dev/null | grep -q ":$port "; then
                printf "  端口监听: ${GREEN}正常${NC}\n"
            else
                printf "  端口监听: ${RED}异常${NC}\n"
            fi
        fi
    else
        printf "${RED}✗${NC} %s: 未配置\n" "$MODULE_NAME"
    fi
}

# ============ 验证安装 (内部函数) ============
verify_installation() {
    # 验证SSH服务运行
    if ! systemctl is-active ssh >/dev/null 2>&1; then
        log_error "SSH服务未运行"
        return 1
    fi

    # 验证端口监听
    sleep 2
    if ! netstat -tuln 2>/dev/null | grep -q ":$CONFIGURED_PORT "; then
        log_error "SSH端口 $CONFIGURED_PORT 未监听"
        return 1
    fi

    return 0
}

# ============ 安装后信息 (可选) ============
show_post_install_info() {
    local ip=$(get_server_ip)

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}SSH配置完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}连接信息:${NC}
  主机: ${GREEN}$ip${NC}
  端口: ${GREEN}$CONFIGURED_PORT${NC}
  用户: ${GREEN}$CONFIGURED_USER${NC}
  认证: ${GREEN}SSH密钥${NC}

${BOLD}测试连接 (请${RED}不要关闭${NC}当前会话):${NC}

${CYAN}Windows (PowerShell):${NC}
  ssh -p $CONFIGURED_PORT -i "\$env:USERPROFILE\\.ssh\\${CONFIGURED_USER}_ed25519" $CONFIGURED_USER@$ip

${CYAN}Linux/MacOS:${NC}
  ssh -p $CONFIGURED_PORT -i ~/.ssh/${CONFIGURED_USER}_ed25519 $CONFIGURED_USER@$ip

${RED}${BOLD}重要提示:${NC}
  1. ${RED}请在新终端测试连接,确认可以登录后再关闭当前会话${NC}
  2. root登录已禁用
  3. 密码认证已禁用
  4. 配置备份: $SSH_CONFIG_BACKUP

${BOLD}下一步:${NC}
  建议配置Fail2Ban (选项5) 和防火墙 (选项6)

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
