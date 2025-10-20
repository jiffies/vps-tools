#!/bin/bash
# modules/install/docker.sh
# Docker 和 Docker Compose 安装模块

# ============ 模块元数据 ============
MODULE_NAME="Docker"
MODULE_VERSION="1.0.0"
MODULE_DEPS=""
MODULE_CATEGORY="install"
MODULE_DESC="安装 Docker Engine 和 Docker Compose V2"

# ============ 全局变量 ============
DOCKER_FLAG="/var/lib/docker/installed.flag"

# ============ 检查函数 ============
check_installed() {
    if command -v docker &>/dev/null; then
        return 0
    fi
    return 1
}

check_dependencies() {
    # Docker 没有依赖其他模块
    return 0
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    # 检查是否已安装
    if check_installed; then
        log_warning "Docker 已安装"
        local version=$(docker --version)
        log_info "当前版本: $version"

        if ! ask_yes_no "是否重新安装?"; then
            return 0
        fi

        # 卸载旧版本
        log_info "卸载旧版本..."
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    fi

    # 检查网络连接
    if ! check_internet; then
        log_error "无法连接到互联网,安装失败"
        return 1
    fi

    # 步骤1: 更新包索引
    log_step 1 8 "更新包索引"
    if ! apt-get update; then
        log_error "更新包索引失败"
        return 1
    fi

    # 步骤2: 安装依赖包
    log_step 2 8 "安装必要的依赖包"
    if ! apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release; then
        log_error "安装依赖包失败"
        return 1
    fi

    # 步骤3: 添加Docker官方GPG密钥
    log_step 3 8 "添加Docker官方GPG密钥"
    mkdir -p /etc/apt/keyrings

    # 使用HTTPS下载GPG密钥(修复安全问题!)
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
        log_error "添加GPG密钥失败"
        return 1
    fi

    chmod a+r /etc/apt/keyrings/docker.gpg

    # 步骤4: 设置Docker仓库
    log_step 4 8 "设置Docker稳定版仓库"
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 步骤5: 再次更新包索引
    log_step 5 8 "更新包索引"
    if ! apt-get update; then
        log_error "更新包索引失败"
        return 1
    fi

    # 步骤6: 安装Docker Engine
    log_step 6 8 "安装Docker Engine"
    if ! apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin; then
        log_error "安装Docker失败"
        return 1
    fi

    # 步骤7: 启动Docker服务
    log_step 7 8 "启动Docker服务"
    systemctl start docker
    systemctl enable docker

    if ! systemctl is-active --quiet docker; then
        log_error "Docker服务启动失败"
        return 1
    fi

    # 步骤8: 验证安装
    log_step 8 8 "验证安装"
    if ! docker --version &>/dev/null; then
        log_error "Docker安装验证失败"
        return 1
    fi

    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose安装验证失败"
        return 1
    fi

    # 创建安装标记
    mkdir -p /var/lib/docker
    touch "$DOCKER_FLAG"

    # 添加当前用户到docker组(如果不是root)
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        log_info "将用户 $SUDO_USER 添加到 docker 组"
        usermod -aG docker "$SUDO_USER"
    fi

    log_success "$MODULE_NAME 安装成功!"
    show_post_install_info

    return 0
}

# ============ 卸载函数 ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "Docker 未安装"
        return 0
    fi

    # 确认卸载
    echo
    log_warning "卸载Docker将停止所有容器并删除Docker相关包"
    if ! ask_yes_no "确定要卸载Docker吗?"; then
        log_info "已取消卸载"
        return 0
    fi

    # 询问是否保留数据
    local keep_data=false
    if ask_yes_no "是否保留Docker数据(镜像、容器、卷)?"; then
        keep_data=true
    fi

    # 停止所有容器
    log_info "停止所有容器..."
    docker stop $(docker ps -aq) 2>/dev/null || true

    # 停止Docker服务
    log_info "停止Docker服务..."
    systemctl stop docker
    systemctl disable docker

    # 卸载Docker包
    log_info "卸载Docker包..."
    apt-get purge -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    apt-get autoremove -y

    # 删除数据
    if [ "$keep_data" = false ]; then
        log_info "删除Docker数据..."
        rm -rf /var/lib/docker
        rm -rf /var/lib/containerd
    else
        log_info "Docker数据已保留在 /var/lib/docker"
    fi

    # 删除配置
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.gpg

    # 删除标记
    rm -f "$DOCKER_FLAG"

    log_success "Docker 卸载完成"
}

# ============ 状态检查 ============
status() {
    if check_installed; then
        local version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        local compose_version=$(docker compose version 2>/dev/null | awk '{print $4}')

        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"
        echo "  版本: $version"
        echo "  Compose: $compose_version"

        if systemctl is-active --quiet docker; then
            echo -e "  状态: ${GREEN}运行中${NC}"
        else
            echo -e "  状态: ${RED}已停止${NC}"
        fi

        # 显示容器数量
        local running=$(docker ps -q 2>/dev/null | wc -l)
        local total=$(docker ps -aq 2>/dev/null | wc -l)
        echo "  容器: $running 运行 / $total 总计"

        # 显示镜像数量
        local images=$(docker images -q 2>/dev/null | wc -l)
        echo "  镜像: $images 个"
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 安装后信息 ============
show_post_install_info() {
    local docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
    local compose_version=$(docker compose version 2>/dev/null | awk '{print $4}')

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Docker 安装完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}版本信息:${NC}
  Docker Engine: ${GREEN}$docker_version${NC}
  Docker Compose: ${GREEN}$compose_version${NC}

${BOLD}验证安装:${NC}
  docker --version
  docker compose version
  docker run hello-world

${YELLOW}${BOLD}重要提示:${NC}
  1. 如果您使用非root用户,需要重新登录以应用docker组权限
  2. 使用 'docker compose' (有空格) 而不是 'docker-compose'
  3. Docker Compose V2 已内置,无需单独安装

${BOLD}常用命令:${NC}
  docker ps                  # 查看运行中的容器
  docker images              # 查看镜像列表
  docker compose up -d       # 启动compose服务
  docker compose down        # 停止compose服务
  docker system prune -a     # 清理未使用的资源

${BOLD}配置文件:${NC}
  /etc/docker/daemon.json    # Docker守护进程配置
  /var/lib/docker/           # Docker数据目录
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# ============ 模块独立运行支持 ============
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
