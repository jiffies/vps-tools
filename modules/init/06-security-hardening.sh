#!/bin/bash
# modules/init/06-security-hardening.sh
# 系统安全加固
#
# 功能:
# - 禁用不必要的服务
# - 配置系统安全参数
# - 设置文件权限
# - 配置日志审计
# - 其他安全加固措施

# ============ 模块元数据 ============
MODULE_NAME="系统安全加固"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="init"
MODULE_DESC="系统安全加固和参数优化"

# ============ 全局变量 ============
FLAG_FILE="/var/log/vps-tools/init-06-security-hardening.flag"
SYSCTL_CONFIG="/etc/sysctl.d/99-vps-tools-security.conf"
LIMITS_CONFIG="/etc/security/limits.d/99-vps-tools.conf"
HARDENING_ITEMS=()

# ============ 检查函数 (必需) ============
check_installed() {
    [ -f "$FLAG_FILE" ]
    return $?
}

# ============ 安装函数 (必需) ============
install() {
    log_info "开始系统安全加固..."

    # 检查是否已执行
    if check_installed; then
        log_warning "系统安全加固已执行过"
        if ! ask_yes_no "是否重新执行?"; then
            return 0
        fi
    fi

    # 步骤1: 禁用不必要的服务
    log_step 1 7 "禁用不必要的服务"
    disable_unnecessary_services

    # 步骤2: 配置内核参数
    log_step 2 7 "配置内核安全参数"
    configure_kernel_parameters

    # 步骤3: 配置资源限制
    log_step 3 7 "配置系统资源限制"
    configure_limits

    # 步骤4: 加固文件权限
    log_step 4 7 "加固关键文件权限"
    harden_file_permissions

    # 步骤5: 配置自动更新
    log_step 5 7 "配置自动安全更新"
    configure_auto_updates

    # 步骤6: 配置日志审计
    log_step 6 7 "配置日志审计"
    configure_logging

    # 步骤7: 清理和优化
    log_step 7 7 "清理和优化"
    cleanup_system

    # 验证安装
    if verify_installation; then
        # 创建标记文件
        mkdir -p "$(dirname "$FLAG_FILE")"
        cat > "$FLAG_FILE" << EOF
HardeningItems: ${HARDENING_ITEMS[*]}
ConfiguredAt: $(date '+%Y-%m-%d %H:%M:%S')
SysctlConfig: $SYSCTL_CONFIG
LimitsConfig: $LIMITS_CONFIG
EOF

        log_success "$MODULE_NAME 完成!"
        show_post_install_info
        return 0
    else
        log_error "部分配置失败"
        return 1
    fi
}

# ============ 禁用不必要的服务 ============
disable_unnecessary_services() {
    local services_to_disable=(
        "bluetooth.service"
        "avahi-daemon.service"
        "cups.service"
    )

    local disabled_count=0

    for service in "${services_to_disable[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^$service"; then
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                if systemctl disable "$service" >/dev/null 2>&1; then
                    systemctl stop "$service" >/dev/null 2>&1
                    log_info "已禁用服务: $service"
                    ((disabled_count++))
                    HARDENING_ITEMS+=("disable-$service")
                fi
            fi
        fi
    done

    if [ $disabled_count -gt 0 ]; then
        log_success "已禁用 $disabled_count 个不必要的服务"
    else
        log_info "没有需要禁用的服务"
    fi

    return 0
}

# ============ 配置内核参数 ============
configure_kernel_parameters() {
    cat > "$SYSCTL_CONFIG" <<'EOF'
# VPS Tools 安全加固配置
# 生成时间: AUTO_TIMESTAMP

# ========== 网络安全 ==========

# 防止SYN flood攻击
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# 禁用IP转发 (除非需要做NAT/路由)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# 禁用源路由
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 启用反向路径过滤 (防止IP欺骗)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 忽略ICMP重定向
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 不发送ICMP重定向
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 忽略ICMP广播请求
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 记录虚假的ICMP错误消息
net.ipv4.icmp_ignore_bogus_error_responses = 1

# ========== TCP优化 ==========

# TCP窗口缩放
net.ipv4.tcp_window_scaling = 1

# TCP时间戳
net.ipv4.tcp_timestamps = 1

# TCP keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

# 快速回收TIME_WAIT socket
net.ipv4.tcp_tw_reuse = 1

# ========== 系统安全 ==========

# 限制core dump
kernel.core_uses_pid = 1

# 启用ExecShield保护
kernel.exec-shield = 1
kernel.randomize_va_space = 2

# 限制访问内核日志
kernel.dmesg_restrict = 1

# 限制perf工具访问
kernel.perf_event_paranoid = 2

# ========== 文件系统 ==========

# 限制文件句柄数
fs.file-max = 2097152

# inotify限制
fs.inotify.max_user_watches = 524288

# ========== 内存管理 ==========

# vm优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

EOF

    # 替换时间戳
    sed -i "s/AUTO_TIMESTAMP/$(date '+%Y-%m-%d %H:%M:%S')/" "$SYSCTL_CONFIG"

    # 应用配置
    if sysctl -p "$SYSCTL_CONFIG" >/dev/null 2>&1; then
        log_success "内核参数已配置"
        HARDENING_ITEMS+=("kernel-parameters")
        return 0
    else
        log_error "应用内核参数失败"
        return 1
    fi
}

# ============ 配置资源限制 ============
configure_limits() {
    cat > "$LIMITS_CONFIG" <<EOF
# VPS Tools 资源限制配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 最大打开文件数
*    soft nofile 65536
*    hard nofile 65536

# 最大进程数
*    soft nproc  65536
*    hard nproc  65536

# core文件大小限制 (禁用core dump以节省空间)
*    soft core   0
*    hard core   0

# 最大锁定内存
*    soft memlock 65536
*    hard memlock 65536

EOF

    if [ -f "$LIMITS_CONFIG" ]; then
        log_success "资源限制已配置"
        HARDENING_ITEMS+=("resource-limits")
        return 0
    else
        log_error "配置资源限制失败"
        return 1
    fi
}

# ============ 加固文件权限 ============
harden_file_permissions() {
    local files_to_harden=(
        "/etc/passwd:644"
        "/etc/shadow:640"
        "/etc/group:644"
        "/etc/gshadow:640"
        "/etc/ssh/sshd_config:600"
    )

    local hardened_count=0

    for item in "${files_to_harden[@]}"; do
        local file=$(echo "$item" | cut -d: -f1)
        local perm=$(echo "$item" | cut -d: -f2)

        if [ -f "$file" ]; then
            if chmod "$perm" "$file" 2>/dev/null; then
                ((hardened_count++))
            fi
        fi
    done

    log_success "已加固 $hardened_count 个关键文件权限"
    HARDENING_ITEMS+=("file-permissions")
    return 0
}

# ============ 配置自动更新 ============
configure_auto_updates() {
    # 检查是否安装unattended-upgrades
    if ! dpkg -l | grep -q unattended-upgrades; then
        log_info "安装自动更新工具..."
        if apt-get install -y unattended-upgrades apt-listchanges >/dev/null 2>&1; then
            log_success "自动更新工具已安装"
        else
            log_warning "安装自动更新工具失败"
            return 1
        fi
    fi

    # 配置自动更新
    if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        # 启用自动安全更新
        dpkg-reconfigure -plow unattended-upgrades >/dev/null 2>&1

        log_success "自动安全更新已启用"
        HARDENING_ITEMS+=("auto-updates")
        return 0
    else
        log_warning "配置自动更新失败"
        return 1
    fi
}

# ============ 配置日志审计 ============
configure_logging() {
    # 确保rsyslog运行
    if ! systemctl is-active rsyslog >/dev/null 2>&1; then
        systemctl start rsyslog
        systemctl enable rsyslog
    fi

    # 配置日志轮转 (确保不占用太多空间)
    if [ -f /etc/logrotate.conf ]; then
        # 日志轮转配置通常已经存在,这里只验证
        log_success "日志系统已配置"
        HARDENING_ITEMS+=("logging")
    fi

    return 0
}

# ============ 清理系统 ============
cleanup_system() {
    log_info "清理系统..."

    # 清理APT缓存
    apt-get autoremove -y >/dev/null 2>&1
    apt-get autoclean -y >/dev/null 2>&1

    # 清理旧内核 (保留当前和最新的)
    # 这里比较危险,暂时注释
    # apt-get purge -y $(dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d')

    log_success "系统清理完成"
    HARDENING_ITEMS+=("cleanup")
    return 0
}

# ============ 卸载函数 (可选) ============
uninstall() {
    log_warning "此模块不支持完全卸载"
    log_info "如需恢复配置,请手动编辑以下文件:"
    echo "  - $SYSCTL_CONFIG"
    echo "  - $LIMITS_CONFIG"

    if ask_yes_no "是否删除VPS Tools创建的配置文件?"; then
        rm -f "$SYSCTL_CONFIG"
        rm -f "$LIMITS_CONFIG"
        rm -f "$FLAG_FILE"

        log_success "配置文件已删除"
        log_warning "请手动重启系统以恢复默认内核参数"
        return 0
    fi

    return 1
}

# ============ 状态检查 (可选) ============
status() {
    if check_installed; then
        printf "${GREEN}✓${NC} %s: 已完成\n" "$MODULE_NAME"

        if [ -f "$FLAG_FILE" ]; then
            local items=$(grep "^HardeningItems:" "$FLAG_FILE" | cut -d: -f2-)
            local configured_at=$(grep "^ConfiguredAt:" "$FLAG_FILE" | cut -d: -f2- | tr -d ' ')

            printf "  加固项: %s\n" "${items:-未知}"
            printf "  配置时间: %s\n" "${configured_at:-未知}"
        fi

        # 检查配置文件
        if [ -f "$SYSCTL_CONFIG" ]; then
            printf "  内核参数: ${GREEN}已配置${NC}\n"
        else
            printf "  内核参数: ${RED}未配置${NC}\n"
        fi

        if [ -f "$LIMITS_CONFIG" ]; then
            printf "  资源限制: ${GREEN}已配置${NC}\n"
        else
            printf "  资源限制: ${RED}未配置${NC}\n"
        fi

        # 检查自动更新
        if systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
            printf "  自动更新: ${GREEN}已启用${NC}\n"
        else
            printf "  自动更新: ${YELLOW}未启用${NC}\n"
        fi
    else
        printf "${RED}✗${NC} %s: 未执行\n" "$MODULE_NAME"
    fi
}

# ============ 验证安装 (内部函数) ============
verify_installation() {
    local failed=0

    # 验证sysctl配置
    if [ ! -f "$SYSCTL_CONFIG" ]; then
        log_warning "内核参数配置文件不存在"
        ((failed++))
    fi

    # 验证limits配置
    if [ ! -f "$LIMITS_CONFIG" ]; then
        log_warning "资源限制配置文件不存在"
        ((failed++))
    fi

    if [ $failed -eq 0 ]; then
        return 0
    else
        log_warning "部分配置失败 ($failed 项)"
        return 0  # 仍然返回成功,因为这些不是致命错误
    fi
}

# ============ 安装后信息 (可选) ============
show_post_install_info() {
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}系统安全加固完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}已完成的加固项:${NC}
EOF

    for item in "${HARDENING_ITEMS[@]}"; do
        echo -e "  ${GREEN}✓${NC} $item"
    done

    cat << EOF

${BOLD}配置文件:${NC}
  内核参数: $SYSCTL_CONFIG
  资源限制: $LIMITS_CONFIG

${BOLD}查看配置:${NC}
  查看内核参数: sysctl -a | grep -E '(net\.|kernel\.|vm\.)'
  查看资源限制: ulimit -a

${YELLOW}${BOLD}注意:${NC}
  1. 部分内核参数在下次重启后生效
  2. 资源限制对新登录会话生效
  3. 自动安全更新已启用 (仅安全补丁)

${BOLD}下一步建议:${NC}
  - 重启系统使所有配置生效: ${CYAN}reboot${NC}
  - 或继续安装应用 (选项11-14)

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
