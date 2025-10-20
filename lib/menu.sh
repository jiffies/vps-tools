#!/bin/bash
# lib/menu.sh - 菜单系统
# VPS工具交互式菜单界面

# 加载依赖
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ============ 主菜单 ============
show_main_menu() {
    clear
    local ip=$(get_server_ip)
    local os=$(get_os_info)
    local mem=$(get_total_memory)
    local disk=$(get_disk_usage)

    cat << EOF
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
           ${BOLD}${GREEN}VPS 一体化配置工具 v2.0${NC}
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${BLUE}系统信息:${NC}
  IP地址: ${GREEN}$ip${NC}
  系统: $os
  内存: $mem  |  磁盘: $disk
  用户: $(whoami)

${CYAN}================================================================${NC}
${GREEN}[系统初始化]${NC}
  ${BOLD}1${NC}.  >> 一键初始化VPS ${YELLOW}(推荐新服务器)${NC}
  ${BOLD}2${NC}.  [] 更新系统
  ${BOLD}3${NC}.  [] 创建用户
  ${BOLD}4${NC}.  [] 配置SSH安全
  ${BOLD}5${NC}.  [] 配置Fail2Ban
  ${BOLD}6${NC}.  [] 配置防火墙
  ${BOLD}7${NC}.  [] 系统安全加固

${BLUE}[应用安装]${NC}
  ${BOLD}11${NC}. >> 一键安装全部应用
  ${BOLD}12${NC}. [] 安装Docker
  ${BOLD}13${NC}. [] 安装Nginx Proxy Manager
  ${BOLD}14${NC}. [] 安装3x-ui

${YELLOW}[系统管理]${NC}
  ${BOLD}21${NC}. [] 查看服务状态
  ${BOLD}22${NC}. [] 备份配置
  ${BOLD}23${NC}. [] 卸载应用
  ${BOLD}24${NC}. [] 查看日志

${MAGENTA}[高级选项]${NC}
  ${BOLD}31${NC}. [] 使用预设配置
  ${BOLD}32${NC}. [] 导出当前配置
  ${BOLD}33${NC}. [] 系统维护工具

  ${BOLD}0${NC}.  << 退出
${CYAN}================================================================${NC}
EOF
}

# ============ 子菜单 ============
show_uninstall_menu() {
    clear
    print_header "卸载应用"
    cat << EOF

请选择要卸载的应用:

  ${BOLD}1${NC}. Docker
  ${BOLD}2${NC}. Nginx Proxy Manager
  ${BOLD}3${NC}. 3x-ui

  ${BOLD}0${NC}. 返回主菜单

EOF
}

show_maintenance_menu() {
    clear
    print_header "系统维护工具"
    cat << EOF

  ${BOLD}1${NC}. 清理系统日志
  ${BOLD}2${NC}. 清理APT缓存
  ${BOLD}3${NC}. 检查磁盘空间
  ${BOLD}4${NC}. 检查系统更新
  ${BOLD}5${NC}. 重启所有服务

  ${BOLD}0${NC}. 返回主菜单

EOF
}

# ============ 输入读取 ============
read_menu_choice() {
    local prompt="${1:-请输入选项}"
    local range="${2:-[0-33]}"
    echo -n "$prompt $range: "
    read -r choice
    echo "$choice"
}

# ============ 等待用户 ============
press_any_key() {
    echo
    read -n 1 -s -r -p "${CYAN}按任意键继续...${NC}"
    echo
}

press_enter() {
    echo
    read -r -p "${CYAN}按 Enter 继续...${NC}"
}

# ============ 确认对话框 ============
confirm_action() {
    local action="$1"
    local warning="${2:-}"

    echo
    print_separator "─" 60
    log_info "即将执行: ${BOLD}$action${NC}"
    if [ -n "$warning" ]; then
        log_warning "$warning"
    fi
    print_separator "─" 60
    echo

    ask_yes_no "确定要继续吗?"
}

confirm_dangerous_action() {
    local action="$1"
    local warning="$2"

    echo
    print_separator "━" 60
    echo -e "${RED}${BOLD}⚠️  警告 ⚠️${NC}"
    print_separator "━" 60
    echo -e "${YELLOW}即将执行: $action${NC}"
    echo -e "${RED}$warning${NC}"
    print_separator "━" 60
    echo

    # 需要输入 yes 确认
    local confirm
    read -p "请输入 'yes' 确认继续: " confirm
    if [ "$confirm" = "yes" ]; then
        return 0
    else
        log_info "操作已取消"
        return 1
    fi
}

# ============ 进度显示 ============
show_task_progress() {
    local task_name="$1"
    local current="$2"
    local total="$3"

    echo -e "${BLUE}[$current/$total]${NC} $task_name"
    show_progress "$current" "$total"
}

# ============ 结果显示 ============
show_result() {
    local title="$1"
    local status="$2"
    local message="$3"

    echo
    print_separator "━" 60
    if [ "$status" = "success" ]; then
        echo -e "${GREEN}${BOLD}✓ $title 成功${NC}"
    elif [ "$status" = "error" ]; then
        echo -e "${RED}${BOLD}✗ $title 失败${NC}"
    else
        echo -e "${YELLOW}${BOLD}⚠ $title${NC}"
    fi
    print_separator "─" 60
    echo "$message"
    print_separator "━" 60
}

# ============ 信息框显示 ============
show_info_box() {
    local title="$1"
    shift
    local lines=("$@")

    echo
    print_separator "┏" 60
    echo -e "  ${BOLD}$title${NC}"
    print_separator "┣" 60
    for line in "${lines[@]}"; do
        echo "  $line"
    done
    print_separator "┗" 60
}

# ============ 列表显示 ============
show_list() {
    local title="$1"
    shift
    local items=("$@")

    echo
    echo -e "${BOLD}$title:${NC}"
    for i in "${!items[@]}"; do
        echo "  $((i+1)). ${items[$i]}"
    done
    echo
}

# ============ 表格显示 ============
show_table_header() {
    local col1="$1"
    local col2="$2"
    local col3="$3"

    printf "${BOLD}%-20s %-30s %-20s${NC}\n" "$col1" "$col2" "$col3"
    print_separator "─" 70
}

show_table_row() {
    local col1="$1"
    local col2="$2"
    local col3="$3"

    printf "%-20s %-30s %-20s\n" "$col1" "$col2" "$col3"
}

# ============ 加载动画 ============
show_spinner() {
    local pid=$1
    local message="$2"
    local delay=0.1
    local spinstr='|/-\'

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] %s" "$spinstr" "$message"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\r"
    done
    printf "    \r"
}

# ============ 选择菜单(通用) ============
# 用法: choice=$(select_from_list "选择一项" "选项1" "选项2" "选项3")
select_from_list() {
    local title="$1"
    shift
    local options=("$@")

    echo
    echo -e "${BOLD}$title:${NC}"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done
    echo "  0. 取消"
    echo

    while true; do
        read -p "请选择 [0-${#options[@]}]: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -eq 0 ]; then
                return 1
            elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
                echo "${options[$((choice-1))]}"
                return 0
            fi
        fi

        log_error "无效选择,请重试"
    done
}

# ============ 多选菜单 ============
# 用法: selected=$(select_multiple "选择多项(空格分隔)" "选项1" "选项2" "选项3")
select_multiple() {
    local title="$1"
    shift
    local options=("$@")

    echo
    echo -e "${BOLD}$title:${NC}"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done
    echo

    read -p "请输入选项编号(用空格分隔,例如: 1 3 5): " -a choices

    local selected=()
    for choice in "${choices[@]}"; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            selected+=("${options[$((choice-1))]}")
        fi
    done

    if [ ${#selected[@]} -gt 0 ]; then
        echo "${selected[@]}"
        return 0
    else
        return 1
    fi
}

# ============ 显示模块状态 ============
show_module_status() {
    local module_name="$1"
    local is_installed="$2"
    local is_running="$3"
    local extra_info="$4"

    if [ "$is_installed" = "true" ]; then
        echo -ne "${GREEN}✓${NC} "
    else
        echo -ne "${RED}✗${NC} "
    fi

    printf "%-30s" "$module_name"

    if [ "$is_installed" = "true" ]; then
        if [ "$is_running" = "true" ]; then
            echo -ne "${GREEN}运行中${NC}"
        else
            echo -ne "${YELLOW}已停止${NC}"
        fi
    else
        echo -ne "${RED}未安装${NC}"
    fi

    if [ -n "$extra_info" ]; then
        echo -e "  $extra_info"
    else
        echo
    fi
}

# ============ 显示安装完成信息 ============
show_installation_complete() {
    local app_name="$1"
    local url="$2"
    local username="$3"
    local password="$4"
    shift 4
    local tips=("$@")

    echo
    print_separator "━" 70
    echo -e "${GREEN}${BOLD}  🎉 $app_name 安装完成!${NC}"
    print_separator "━" 70

    if [ -n "$url" ]; then
        echo -e "${BOLD}访问地址:${NC}"
        echo -e "  ${CYAN}$url${NC}"
        echo
    fi

    if [ -n "$username" ] && [ -n "$password" ]; then
        echo -e "${BOLD}默认凭据:${NC}"
        echo -e "  用户名: ${YELLOW}$username${NC}"
        echo -e "  密码: ${YELLOW}$password${NC}"
        echo
    fi

    if [ ${#tips[@]} -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}重要提示:${NC}"
        for tip in "${tips[@]}"; do
            echo -e "  • $tip"
        done
        echo
    fi

    print_separator "━" 70
}

# ============ 显示错误信息 ============
show_error_details() {
    local error_title="$1"
    local error_message="$2"
    local log_file="$3"

    echo
    print_separator "━" 70
    echo -e "${RED}${BOLD}✗ 错误: $error_title${NC}"
    print_separator "─" 70
    echo -e "$error_message"

    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        echo
        echo -e "${YELLOW}详细日志:${NC}"
        echo -e "  $log_file"
        echo
        echo -e "最后10行日志:"
        print_separator "─" 70
        tail -n 10 "$log_file" | sed 's/^/  /'
    fi

    print_separator "━" 70
}

# ============ 显示命令帮助 ============
show_command_help() {
    local app_name="$1"
    local install_dir="$2"
    shift 2
    local commands=("$@")

    echo
    echo -e "${BOLD}$app_name 管理命令:${NC}"
    echo

    for cmd in "${commands[@]}"; do
        echo -e "  ${CYAN}$cmd${NC}"
    done
    echo
}

# ============ 导出函数供其他脚本使用 ============
