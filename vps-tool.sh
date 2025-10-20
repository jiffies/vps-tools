#!/bin/bash
# vps-tool.sh - VPS一体化配置工具主入口
# 版本: 2.0
# 作者: VPS Tools Team
# 说明: 统一的VPS初始化和应用安装工具

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载核心库
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/menu.sh"
source "$SCRIPT_DIR/lib/module-loader.sh"

# ============ 全局变量 ============
VERSION="2.0"
CONFIG_DIR="$SCRIPT_DIR/config"
PRESET_DIR="$CONFIG_DIR/presets"

# ============ 初始化 ============
initialize() {
    # 检查root权限
    check_root

    # 创建必要目录
    mkdir -p "$SCRIPT_DIR/logs"
    mkdir -p "$SCRIPT_DIR/backup"
    mkdir -p "$CONFIG_DIR/templates"
    mkdir -p "$PRESET_DIR"

    # 设置日志文件
    export LOG_FILE="$SCRIPT_DIR/logs/vps-tools.log"

    log_debug "VPS Tool v$VERSION 已启动"
    log_debug "脚本目录: $SCRIPT_DIR"
}

# ============ 一键初始化VPS ============
run_init_all() {
    print_header "一键初始化VPS"

    if ! confirm_action "一键初始化VPS" "此操作将依次执行所有系统初始化步骤"; then
        return 1
    fi

    local modules=(
        "01-system-update"
        "02-create-user"
        "03-ssh-config"
        "04-fail2ban"
        "05-firewall"
        "06-security-hardening"
    )

    run_modules_batch "init" "${modules[@]}"
    local result=$?

    if [ $result -eq 0 ]; then
        show_result "VPS初始化" "success" "所有步骤执行成功!"
    else
        show_result "VPS初始化" "error" "部分步骤执行失败,请查看日志"
    fi

    return $result
}

# ============ 一键安装全部应用 ============
run_install_all() {
    print_header "一键安装全部应用"

    if ! confirm_action "一键安装全部应用" "将安装 Docker、Nginx Proxy Manager 和 3x-ui"; then
        return 1
    fi

    local modules=(
        "docker"
        "nginx-proxy-manager"
        "3x-ui"
    )

    run_modules_batch "install" "${modules[@]}"
    local result=$?

    if [ $result -eq 0 ]; then
        show_result "应用安装" "success" "所有应用安装成功!"
    else
        show_result "应用安装" "error" "部分应用安装失败,请查看日志"
    fi

    return $result
}

# ============ 显示服务状态 ============
show_status() {
    show_all_modules_status
}

# ============ 备份配置 ============
run_backup() {
    print_header "备份配置"

    local backup_dir="$SCRIPT_DIR/backup/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    log_info "备份目录: $backup_dir"

    # 备份系统配置文件
    local files_to_backup=(
        "/etc/ssh/sshd_config"
        "/etc/fail2ban/jail.local"
        "/etc/ufw/user.rules"
    )

    for file in "${files_to_backup[@]}"; do
        if [ -f "$file" ]; then
            cp -p "$file" "$backup_dir/" && log_success "已备份: $file"
        fi
    done

    # 备份应用数据
    if [ -d "/opt/npm" ]; then
        tar -czf "$backup_dir/npm-data.tar.gz" -C /opt npm 2>/dev/null && \
            log_success "已备份: Nginx Proxy Manager 数据"
    fi

    log_success "备份完成: $backup_dir"
}

# ============ 卸载菜单 ============
run_uninstall_menu() {
    while true; do
        show_uninstall_menu
        choice=$(read_menu_choice "请选择" "[0-3]")

        case $choice in
            0)
                return 0
                ;;
            1)
                run_module "install" "docker" "uninstall"
                ;;
            2)
                run_module "install" "nginx-proxy-manager" "uninstall"
                ;;
            3)
                run_module "install" "3x-ui" "uninstall"
                ;;
            *)
                log_error "无效选项: $choice"
                ;;
        esac

        press_any_key
    done
}

# ============ 查看日志 ============
show_logs() {
    print_header "查看日志"

    if [ ! -f "$LOG_FILE" ]; then
        log_warning "日志文件不存在: $LOG_FILE"
        return 1
    fi

    echo -e "${BOLD}日志文件:${NC} $LOG_FILE"
    echo
    echo -e "${BOLD}最后50行:${NC}"
    print_separator "─" 70

    tail -n 50 "$LOG_FILE" | while IFS= read -r line; do
        # 高亮显示不同级别的日志
        if [[ $line =~ ERROR ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ $line =~ WARNING ]]; then
            echo -e "${YELLOW}$line${NC}"
        elif [[ $line =~ SUCCESS ]]; then
            echo -e "${GREEN}$line${NC}"
        else
            echo "$line"
        fi
    done

    print_separator "─" 70
    echo
    echo -e "${CYAN}完整日志文件: $LOG_FILE${NC}"
}

# ============ 使用预设配置 ============
run_preset_config() {
    print_header "使用预设配置"

    # 列出可用预设
    local presets=()
    if [ -d "$PRESET_DIR" ]; then
        for preset in "$PRESET_DIR"/*.conf; do
            if [ -f "$preset" ]; then
                presets+=("$(basename "$preset" .conf)")
            fi
        done
    fi

    if [ ${#presets[@]} -eq 0 ]; then
        log_warning "没有可用的预设配置"
        log_info "预设目录: $PRESET_DIR"
        return 1
    fi

    echo "可用预设:"
    echo
    for i in "${!presets[@]}"; do
        echo "  $((i+1)). ${presets[$i]}"
    done
    echo "  0. 取消"
    echo

    read -p "请选择预设 [0-${#presets[@]}]: " choice

    if [ "$choice" = "0" ]; then
        return 0
    elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#presets[@]}" ]; then
        local preset_name="${presets[$((choice-1))]}"
        local preset_file="$PRESET_DIR/${preset_name}.conf"

        log_info "使用预设: $preset_name"

        # TODO: 实现预设配置加载和应用
        log_warning "预设配置功能尚未实现"
    else
        log_error "无效选择"
    fi
}

# ============ 导出当前配置 ============
export_config() {
    print_header "导出当前配置"

    local export_file="$SCRIPT_DIR/config/export_$(date +%Y%m%d_%H%M%S).conf"

    log_info "导出配置到: $export_file"

    cat > "$export_file" << EOF
# VPS工具配置导出
# 导出时间: $(date '+%Y-%m-%d %H:%M:%S')

# 系统信息
SYSTEM_IP=$(get_server_ip)
SYSTEM_OS=$(get_os_info)

# 已安装模块
EOF

    get_installed_modules | while read -r module; do
        echo "INSTALLED_MODULE=$module" >> "$export_file"
    done

    log_success "配置已导出: $export_file"
}

# ============ 系统维护工具 ============
run_maintenance() {
    while true; do
        show_maintenance_menu
        choice=$(read_menu_choice "请选择" "[0-5]")

        case $choice in
            0)
                return 0
                ;;
            1)
                # 清理系统日志
                if confirm_action "清理系统日志" "将清理超过7天的日志"; then
                    journalctl --vacuum-time=7d
                    log_success "系统日志已清理"
                fi
                ;;
            2)
                # 清理APT缓存
                if confirm_action "清理APT缓存"; then
                    apt-get clean
                    apt-get autoclean
                    apt-get autoremove -y
                    log_success "APT缓存已清理"
                fi
                ;;
            3)
                # 检查磁盘空间
                echo
                df -h
                echo
                du -sh /var/log/* 2>/dev/null | sort -hr | head -10
                ;;
            4)
                # 检查系统更新
                log_info "检查系统更新..."
                apt-get update -qq
                apt-get list --upgradable
                ;;
            5)
                # 重启所有服务
                if confirm_dangerous_action "重启所有服务" "此操作将重启Docker、Nginx等服务"; then
                    service_restart ssh
                    service_restart fail2ban
                    if check_command docker; then
                        systemctl restart docker
                    fi
                    log_success "所有服务已重启"
                fi
                ;;
            *)
                log_error "无效选项: $choice"
                ;;
        esac

        press_any_key
    done
}

# ============ 主循环 ============
main_loop() {
    while true; do
        show_main_menu
        choice=$(read_menu_choice)

        case $choice in
            0)
                log_info "退出程序"
                echo
                echo -e "${GREEN}感谢使用 VPS Tools!${NC}"
                echo
                exit 0
                ;;

            # 系统初始化
            1)
                run_init_all
                ;;
            2)
                run_module "init" "01-system-update" "install"
                ;;
            3)
                run_module "init" "02-create-user" "install"
                ;;
            4)
                run_module "init" "03-ssh-config" "install"
                ;;
            5)
                run_module "init" "04-fail2ban" "install"
                ;;
            6)
                run_module "init" "05-firewall" "install"
                ;;
            7)
                run_module "init" "06-security-hardening" "install"
                ;;

            # 应用安装
            11)
                run_install_all
                ;;
            12)
                run_module "install" "docker" "install"
                ;;
            13)
                run_module "install" "nginx-proxy-manager" "install"
                ;;
            14)
                run_module "install" "3x-ui" "install"
                ;;

            # 系统管理
            21)
                show_status
                ;;
            22)
                run_backup
                ;;
            23)
                run_uninstall_menu
                ;;
            24)
                show_logs
                ;;

            # 高级选项
            31)
                run_preset_config
                ;;
            32)
                export_config
                ;;
            33)
                run_maintenance
                ;;

            *)
                log_error "无效选项: $choice"
                ;;
        esac

        press_any_key
    done
}

# ============ 命令行参数处理 ============
handle_arguments() {
    case "${1:-}" in
        -h|--help)
            cat << EOF
VPS 一体化配置工具 v$VERSION

用法: $0 [选项]

选项:
  -h, --help          显示帮助信息
  -v, --version       显示版本信息
  -l, --list          列出所有可用模块
  --init              一键初始化VPS
  --install-all       一键安装全部应用
  --status            显示所有服务状态

示例:
  $0                  启动交互式菜单
  $0 --init           直接执行一键初始化
  $0 --status         查看服务状态

EOF
            exit 0
            ;;
        -v|--version)
            echo "VPS Tools v$VERSION"
            exit 0
            ;;
        -l|--list)
            list_modules
            exit 0
            ;;
        --init)
            run_init_all
            exit $?
            ;;
        --install-all)
            run_install_all
            exit $?
            ;;
        --status)
            show_status
            exit 0
            ;;
        "")
            # 无参数,启动交互模式
            return 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 $0 --help 查看帮助"
            exit 1
            ;;
    esac
}

# ============ 主程序入口 ============
main() {
    # 初始化
    initialize

    # 处理命令行参数
    handle_arguments "$@"

    # 进入主循环
    main_loop
}

# 执行主程序
main "$@"
