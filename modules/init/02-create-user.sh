#!/bin/bash
# modules/init/02-create-user.sh
# 创建普通用户并配置sudo权限
#
# 功能:
# - 创建新用户并设置密码
# - 添加用户到sudo组
# - 验证用户名有效性
# - 创建用户主目录

# ============ 模块元数据 ============
MODULE_NAME="创建用户"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="init"
MODULE_DESC="创建普通用户并配置sudo权限"

# ============ 全局变量 ============
FLAG_FILE="/var/log/vps-tools/init-02-create-user.flag"
CREATED_USERNAME=""

# ============ 检查函数 (必需) ============
check_installed() {
    # 检查是否已创建过用户
    [ -f "$FLAG_FILE" ]
    return $?
}

# ============ 安装函数 (必需) ============
install() {
    log_info "开始创建新用户..."

    # 检查是否已执行过
    if check_installed; then
        log_warning "之前已创建过用户"
        CREATED_USERNAME=$(cat "$FLAG_FILE" 2>/dev/null)
        if [ -n "$CREATED_USERNAME" ]; then
            log_info "之前创建的用户: $CREATED_USERNAME"
        fi
        if ! ask_yes_no "是否创建新用户?"; then
            return 0
        fi
    fi

    # 步骤1: 输入用户名
    log_step 1 4 "输入新用户名"
    local username
    while true; do
        printf "${BLUE}请输入新用户名: ${NC}"
        read -r username

        # 验证用户名
        if [ -z "$username" ]; then
            log_error "用户名不能为空"
            continue
        fi

        if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            log_error "用户名只能包含小写字母、数字、下划线和连字符,且必须以字母或下划线开头"
            continue
        fi

        if id "$username" &>/dev/null; then
            log_error "用户 $username 已存在"
            continue
        fi

        # 用户名有效
        log_success "用户名 $username 有效"
        break
    done

    CREATED_USERNAME="$username"

    # 步骤2: 创建用户
    log_step 2 4 "创建用户 $username"
    if ! adduser "$username"; then
        log_error "创建用户失败"
        return 1
    fi
    log_success "用户 $username 创建成功"

    # 步骤3: 添加到sudo组
    log_step 3 4 "添加用户到sudo组"
    if ! usermod -aG sudo "$username"; then
        log_error "添加到sudo组失败"
        # 删除刚创建的用户
        userdel -r "$username" 2>/dev/null
        return 1
    fi
    log_success "用户 $username 已添加到sudo组"

    # 步骤4: 验证配置
    log_step 4 4 "验证配置"
    if verify_installation; then
        # 创建标记文件
        mkdir -p "$(dirname "$FLAG_FILE")"
        echo "$username" > "$FLAG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S')" >> "$FLAG_FILE"

        log_success "$MODULE_NAME 完成!"
        show_post_install_info
        return 0
    else
        log_error "验证失败"
        return 1
    fi
}

# ============ 卸载函数 (可选) ============
uninstall() {
    log_warning "此模块不支持卸载"
    log_info "如需删除用户,请手动执行: deluser --remove-home <username>"
    return 1
}

# ============ 状态检查 (可选) ============
status() {
    if check_installed; then
        local username=$(head -n1 "$FLAG_FILE" 2>/dev/null)
        local created_at=$(tail -n1 "$FLAG_FILE" 2>/dev/null)

        printf "${GREEN}✓${NC} %s: 已完成\n" "$MODULE_NAME"

        if [ -n "$username" ]; then
            if id "$username" &>/dev/null; then
                printf "  用户: ${GREEN}%s${NC} (存在)\n" "$username"

                # 检查sudo权限
                if groups "$username" | grep -q sudo; then
                    printf "  Sudo: ${GREEN}已配置${NC}\n"
                else
                    printf "  Sudo: ${RED}未配置${NC}\n"
                fi
            else
                printf "  用户: ${RED}%s${NC} (已删除)\n" "$username"
            fi
        fi

        if [ -n "$created_at" ]; then
            printf "  创建时间: %s\n" "$created_at"
        fi
    else
        printf "${RED}✗${NC} %s: 未执行\n" "$MODULE_NAME"
    fi
}

# ============ 验证安装 (内部函数) ============
verify_installation() {
    # 验证用户是否存在
    if ! id "$CREATED_USERNAME" &>/dev/null; then
        log_error "用户 $CREATED_USERNAME 不存在"
        return 1
    fi

    # 验证用户在sudo组
    if ! groups "$CREATED_USERNAME" | grep -q sudo; then
        log_error "用户 $CREATED_USERNAME 不在sudo组"
        return 1
    fi

    # 验证主目录存在
    if [ ! -d "/home/$CREATED_USERNAME" ]; then
        log_error "用户主目录不存在"
        return 1
    fi

    return 0
}

# ============ 安装后信息 (可选) ============
show_post_install_info() {
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}用户创建完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}用户信息:${NC}
  用户名: ${GREEN}$CREATED_USERNAME${NC}
  主目录: /home/$CREATED_USERNAME
  权限: sudo组成员

${BOLD}测试sudo权限:${NC}
  su - $CREATED_USERNAME
  sudo whoami

${YELLOW}${BOLD}下一步:${NC}
  建议配置SSH密钥认证 (选项3: 配置SSH安全)

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
