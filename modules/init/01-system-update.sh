#!/bin/bash
# modules/init/01-system-update.sh
# 系统更新模块

MODULE_NAME="系统更新"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="init"

check_installed() {
    # 系统更新不需要检查是否已安装
    return 1
}

install() {
    log_info "开始更新系统..."

    if ! check_internet; then
        log_error "无法连接到互联网"
        return 1
    fi

    log_step 1 3 "更新软件包列表"
    if ! apt-get update; then
        log_error "更新软件包列表失败"
        return 1
    fi

    log_step 2 3 "升级已安装的软件包"
    if ask_yes_no "是否升级所有软件包?" "y"; then
        apt-get upgrade -y
    fi

    log_step 3 3 "安装基础工具"
    apt-get install -y \
        curl \
        wget \
        vim \
        git \
        net-tools \
        htop \
        ufw \
        fail2ban \
        sudo

    log_success "系统更新完成!"
    return 0
}

status() {
    echo -e "${BLUE}ℹ${NC} $MODULE_NAME: 系统维护任务"
}

if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    source "$SCRIPT_DIR/lib/common.sh"
    install
fi
