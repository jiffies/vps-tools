#!/bin/bash
# modules/install/nginx-proxy-manager.sh
# Nginx Proxy Manager 安装模块
# 已修复: 网络模式从 host 改为桥接模式(安全)

# ============ 模块元数据 ============
MODULE_NAME="Nginx Proxy Manager"
MODULE_VERSION="1.0.0"
MODULE_DEPS="docker"
MODULE_CATEGORY="install"
MODULE_DESC="安装 Nginx Proxy Manager (反向代理管理面板)"

# ============ 全局变量 ============
NPM_DIR="/opt/npm"
NPM_FLAG="$NPM_DIR/installed.flag"

# ============ 检查函数 ============
check_installed() {
    [ -f "$NPM_FLAG" ] && [ -d "$NPM_DIR" ]
}

check_dependencies() {
    if ! command -v docker &>/dev/null; then
        log_error "需要先安装 Docker"
        return 1
    fi

    if ! systemctl is-active --quiet docker; then
        log_error "Docker 服务未运行"
        return 1
    fi

    return 0
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    # 检查依赖
    if ! check_dependencies; then
        if ask_yes_no "是否现在安装 Docker?"; then
            if [ -f "$SCRIPT_DIR/modules/install/docker.sh" ]; then
                source "$SCRIPT_DIR/modules/install/docker.sh"
                install || return 1
            else
                log_error "找不到 Docker 安装模块"
                return 1
            fi
        else
            return 1
        fi
    fi

    # 检查是否已安装
    if check_installed; then
        log_warning "$MODULE_NAME 已安装"

        if ! ask_yes_no "是否重新安装?"; then
            return 0
        fi

        # 备份现有数据
        if ask_yes_no "是否备份现有数据?"; then
            local backup_dir="$NPM_DIR.backup.$(date +%Y%m%d_%H%M%S)"
            log_info "备份到: $backup_dir"
            cp -r "$NPM_DIR" "$backup_dir"
        fi

        # 停止现有服务
        log_info "停止现有服务..."
        cd "$NPM_DIR" && docker compose down 2>/dev/null || true
    fi

    # 步骤1: 创建目录
    log_step 1 6 "创建目录结构"
    mkdir -p "$NPM_DIR"/{data,letsencrypt}

    if [ ! -d "$NPM_DIR" ]; then
        log_error "创建目录失败"
        return 1
    fi

    cd "$NPM_DIR" || return 1

    # 步骤2: 创建docker-compose.yml (修复网络安全问题!)
    log_step 2 6 "创建配置文件 (使用安全的桥接网络模式)"

    cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  app:
    image: "jc21/nginx-proxy-manager:latest"
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"      # HTTP
      - "81:81"      # 管理面板
      - "443:443"    # HTTPS
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
      DISABLE_IPV6: "true"
    networks:
      - npm_network
    healthcheck:
      test: ["CMD", "/bin/check-health"]
      interval: 10s
      timeout: 3s

networks:
  npm_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

    log_success "配置文件已创建 (使用桥接网络,而非不安全的host模式)"

    # 步骤3: 设置权限
    log_step 3 6 "设置目录权限"
    chmod -R 755 "$NPM_DIR"

    # 步骤4: 拉取镜像
    log_step 4 6 "拉取Docker镜像"
    if ! docker compose pull; then
        log_error "拉取镜像失败"
        return 1
    fi

    # 步骤5: 启动服务
    log_step 5 6 "启动服务"
    if ! docker compose up -d; then
        log_error "启动服务失败"
        docker compose logs
        return 1
    fi

    # 步骤6: 验证安装
    log_step 6 6 "验证安装"

    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10

    # 检查容器状态
    if ! docker ps | grep -q nginx-proxy-manager; then
        log_error "容器未正常运行"
        docker compose logs --tail=50
        return 1
    fi

    # 检查端口
    if ! wait_for_port localhost 81 30; then
        log_warning "管理面板端口(81)未就绪,但容器正在运行"
        log_info "服务可能需要更多时间启动,请稍后访问"
    fi

    # 创建安装标记
    touch "$NPM_FLAG"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$NPM_FLAG"

    log_success "$MODULE_NAME 安装成功!"
    show_post_install_info

    return 0
}

# ============ 卸载函数 ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    # 确认卸载
    echo
    log_warning "卸载 Nginx Proxy Manager 将停止所有代理配置"
    if ! ask_yes_no "确定要卸载吗?"; then
        log_info "已取消卸载"
        return 0
    fi

    # 进入目录
    cd "$NPM_DIR" || {
        log_error "目录不存在: $NPM_DIR"
        return 1
    }

    # 停止服务
    log_info "停止服务..."
    docker compose down

    # 询问是否保留数据
    local keep_data=false
    if ask_yes_no "是否保留数据(代理配置、SSL证书)?"; then
        keep_data=true
    fi

    if [ "$keep_data" = true ]; then
        # 备份数据
        local backup_dir="$NPM_DIR.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "备份数据到: $backup_dir"
        mv "$NPM_DIR" "$backup_dir"
        log_success "数据已备份"
    else
        # 删除所有数据
        log_info "删除所有数据..."
        rm -rf "$NPM_DIR"
        log_success "数据已删除"
    fi

    log_success "$MODULE_NAME 卸载完成"
}

# ============ 状态检查 ============
status() {
    if check_installed; then
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"

        # 检查容器状态
        if docker ps --format '{{.Names}}' | grep -q nginx-proxy-manager; then
            echo -e "  状态: ${GREEN}运行中${NC}"

            # 获取容器信息
            local uptime=$(docker ps --filter name=nginx-proxy-manager --format "{{.Status}}")
            echo "  运行时间: $uptime"

            # 检查端口
            echo "  端口映射:"
            docker port nginx-proxy-manager 2>/dev/null | while read -r line; do
                echo "    $line"
            done

            # 检查网络模式
            local network=$(docker inspect nginx-proxy-manager --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null)
            echo "  网络: ${GREEN}$network${NC} (桥接模式 - 安全)"

        else
            echo -e "  状态: ${RED}已停止${NC}"
        fi

        echo "  安装目录: $NPM_DIR"
        echo "  数据大小: $(du -sh "$NPM_DIR"/data 2>/dev/null | awk '{print $1}')"
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

# ============ 安装后信息 ============
show_post_install_info() {
    local ip=$(get_server_ip)

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}${BOLD}Nginx Proxy Manager 安装完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}访问信息:${NC}
  管理面板: ${CYAN}http://$ip:81${NC}
  HTTP端口: 80
  HTTPS端口: 443

${BOLD}默认凭据:${NC}
  邮箱: ${YELLOW}admin@example.com${NC}
  密码: ${YELLOW}changeme${NC}

${RED}${BOLD}安全改进:${NC}
  ✓ 使用桥接网络模式(安全)
  ✓ 明确端口映射: 80, 81, 443
  ✗ 已弃用 host 网络模式(不安全)

${YELLOW}${BOLD}重要提示:${NC}
  1. ${RED}请立即登录并修改默认密码!${NC}
  2. 首次登录后需要设置新的邮箱和密码
  3. 建议配置SSL证书(支持Let's Encrypt自动申请)

EOF

    # 检查是否安装了 ufw-docker
    if [ -x /usr/local/bin/ufw-docker ]; then
        local container_name=$(docker ps --filter ancestor=jc21/nginx-proxy-manager:latest --format "{{.Names}}" 2>/dev/null | head -1)
        if [ -z "$container_name" ]; then
            container_name="nginx-proxy-manager-app-1"
        fi

        cat << EOF
${RED}${BOLD}⚠️  防火墙配置required!${NC}

${YELLOW}容器端口默认不对外开放,需要手动配置防火墙:${NC}

${BOLD}开放端口命令 (必须执行):${NC}

  # 1. 允许所有人访问 HTTP/HTTPS (网站访问)
  ${GREEN}sudo ufw-docker allow $container_name 80${NC}
  ${GREEN}sudo ufw-docker allow $container_name 443${NC}

  # 2. 管理端口 (推荐只允许你的IP访问)
  ${YELLOW}sudo ufw-docker allow $container_name 81 YOUR_IP_ADDRESS${NC}

  # 或者允许所有人访问管理端口 (不推荐)
  ${YELLOW}sudo ufw-docker allow $container_name 81${NC}

${BOLD}查看容器名称:${NC}
  docker ps --format "{{.Names}}"

${BOLD}检查端口状态:${NC}
  sudo ufw-docker list

${RED}${BOLD}注意:${NC}
  - ${RED}在开放端口之前,无法从外部访问服务${NC}
  - 这是安全的默认行为
  - 建议限制管理端口(81)只允许特定IP访问

EOF
    else
        cat << EOF
${YELLOW}${BOLD}防火墙配置:${NC}
  如果启用了UFW,需要开放以下端口:

  ${GREEN}sudo ufw allow 80/tcp comment 'HTTP'${NC}
  ${GREEN}sudo ufw allow 443/tcp comment 'HTTPS'${NC}
  ${YELLOW}sudo ufw allow 81/tcp comment 'NPM Admin'${NC}

EOF
    fi

    cat << EOF
${BOLD}管理命令:${NC}
  启动服务:
    ${CYAN}cd $NPM_DIR && docker compose up -d${NC}

  停止服务:
    ${CYAN}cd $NPM_DIR && docker compose down${NC}

  重启服务:
    ${CYAN}cd $NPM_DIR && docker compose restart${NC}

  查看日志:
    ${CYAN}cd $NPM_DIR && docker compose logs -f${NC}

  更新版本:
    ${CYAN}cd $NPM_DIR && docker compose pull && docker compose up -d${NC}

${BOLD}配置文件:${NC}
  Docker Compose: $NPM_DIR/docker-compose.yml
  数据目录: $NPM_DIR/data
  SSL证书: $NPM_DIR/letsencrypt

${BOLD}常见用途:${NC}
  • 反向代理管理(支持HTTP/HTTPS)
  • Let's Encrypt SSL证书自动申请和续期
  • 访问列表(Access List)权限控制
  • 流量重定向和负载均衡

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# ============ 模块独立运行支持 ============
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
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
