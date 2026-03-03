# VPS工具脚本重构设计方案

## 设计目标

1. **合二为一**: 将 initVPS.sh 和 installApp.sh 合并为统一工具
2. **模块化架构**: 每个功能独立模块,方便添加新配置/新安装
3. **交互式菜单**: 支持选择性执行,支持一键全自动
4. **安全优先**: 修复所有P0/P1安全问题
5. **易于扩展**: 新增功能只需添加一个模块文件

## 新架构设计

```
vps-tools/
├── vps-tool.sh                    # 主入口(唯一需要执行的脚本)
│
├── lib/                           # 核心库
│   ├── common.sh                  # 通用函数(日志、颜色、输入验证等)
│   ├── menu.sh                    # 菜单系统
│   └── module-loader.sh           # 模块加载器
│
├── modules/                       # 功能模块(每个文件一个功能)
│   ├── init/                      # 初始化模块
│   │   ├── 01-system-update.sh
│   │   ├── 02-create-user.sh
│   │   ├── 03-ssh-config.sh
│   │   ├── 04-fail2ban.sh
│   │   ├── 05-firewall.sh
│   │   └── 06-security-hardening.sh
│   │
│   ├── install/                   # 安装模块
│   │   ├── docker.sh
│   │   ├── nginx-proxy-manager.sh
│   │   ├── s-ui.sh
│   │   └── caddy.sh              # 示例:以后可以轻松添加
│   │
│   └── manage/                    # 管理模块
│       ├── backup.sh
│       ├── status.sh
│       └── uninstall.sh
│
├── config/                        # 配置模板
│   ├── templates/
│   │   ├── sshd_config.template
│   │   ├── fail2ban-jail.template
│   │   ├── npm-compose.yml
│   │   └── ufw-rules.template
│   │
│   └── presets/                   # 预设配置(支持非交互模式)
│       ├── minimal.conf           # 最小化配置
│       ├── standard.conf          # 标准配置
│       └── full.conf              # 完整配置
│
├── logs/                          # 日志目录
│   └── .gitkeep
│
├── backup/                        # 备份目录
│   └── .gitkeep
│
├── README.md                      # 使用文档
└── CLAUDE.md                      # Claude指导文档
```

## 主菜单设计

```bash
============================================
         VPS 一体化配置工具 v2.0
============================================
系统信息:
  IP地址: 192.168.1.100
  系统: Ubuntu 22.04 LTS
  用户: root

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[系统初始化]
  1. 一键初始化VPS(推荐新服务器)
  2. 更新系统
  3. 创建用户
  4. 配置SSH安全
  5. 配置Fail2Ban
  6. 配置防火墙
  7. 系统安全加固

[应用安装]
  11. 一键安装全部应用
  12. 安装Docker
  13. 安装Nginx Proxy Manager
  14. 安装s-ui
  15. 安装Caddy (示例)

[系统管理]
  21. 查看服务状态
  22. 备份配置
  23. 卸载应用
  24. 查看日志

[高级选项]
  31. 使用预设配置(非交互模式)
  32. 导出当前配置
  33. 恢复配置

  0. 退出
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
请输入选项 [0-33]:
```

## 模块化标准规范

### 每个模块文件结构

```bash
#!/bin/bash
# modules/install/example.sh
#
# 模块名称: Example应用安装
# 依赖: docker
# 描述: 安装并配置Example应用

# ============ 模块元数据 ============
MODULE_NAME="Example"
MODULE_VERSION="1.0.0"
MODULE_DEPS="docker"  # 依赖的其他模块,空格分隔
MODULE_CATEGORY="install"

# ============ 检查函数 ============
# 检查模块是否已安装
check_installed() {
    [ -f "/opt/example/installed.flag" ]
    return $?
}

# 检查依赖是否满足
check_dependencies() {
    for dep in $MODULE_DEPS; do
        if ! check_module_installed "$dep"; then
            log_error "依赖 $dep 未安装"
            return 1
        fi
    done
    return 0
}

# ============ 安装函数 ============
install() {
    log_info "开始安装 $MODULE_NAME..."

    # 检查依赖
    check_dependencies || return 1

    # 检查是否已安装
    if check_installed; then
        log_warning "$MODULE_NAME 已安装"
        ask_yes_no "是否重新安装?" || return 0
    fi

    # 步骤1
    log_step 1 5 "创建目录"
    mkdir -p /opt/example || return 1

    # 步骤2
    log_step 2 5 "下载配置"
    # ...

    # 步骤3
    log_step 3 5 "配置服务"
    # ...

    # 步骤4
    log_step 4 5 "启动服务"
    # ...

    # 步骤5
    log_step 5 5 "验证安装"
    if verify_installation; then
        touch /opt/example/installed.flag
        log_success "$MODULE_NAME 安装成功!"
        show_post_install_info
        return 0
    else
        log_error "$MODULE_NAME 安装失败"
        return 1
    fi
}

# ============ 卸载函数 ============
uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    ask_yes_no "是否保留数据?"
    local keep_data=$?

    # 停止服务
    docker-compose -f /opt/example/docker-compose.yml down

    # 删除文件
    if [ $keep_data -eq 1 ]; then
        rm -rf /opt/example
    else
        mv /opt/example /opt/example.backup.$(date +%Y%m%d_%H%M%S)
        log_info "数据已备份"
    fi

    log_success "$MODULE_NAME 卸载完成"
}

# ============ 状态检查 ============
status() {
    if check_installed; then
        echo "✓ $MODULE_NAME: 已安装"
        # 显示详细状态
        docker ps | grep example
    else
        echo "✗ $MODULE_NAME: 未安装"
    fi
}

# ============ 安装后信息 ============
show_post_install_info() {
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  $MODULE_NAME 安装完成!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
访问地址: http://$(get_server_ip):8080
默认用户: admin
默认密码: changeme

重要提示:
  1. 请立即修改默认密码
  2. 建议配置SSL证书

管理命令:
  启动: docker-compose -f /opt/example/docker-compose.yml up -d
  停止: docker-compose -f /opt/example/docker-compose.yml down
  日志: docker-compose -f /opt/example/docker-compose.yml logs -f
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# ============ 验证函数 ============
verify_installation() {
    # 检查服务是否运行
    docker ps | grep -q example
    return $?
}

# ============ 模块入口点 ============
# 当直接执行模块时的行为
if [ "${BASH_SOURCE[0]}" -eq "${0}" ]; then
    # 加载公共库
    source "$(dirname "$0")/../../lib/common.sh"

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
```

## 核心库设计

### lib/common.sh - 通用函数库

```bash
#!/bin/bash
# lib/common.sh - 通用函数库

# ============ 颜色定义 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ============ 日志函数 ============
LOG_FILE="/var/log/vps-tools.log"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

log_step() {
    local current=$1
    local total=$2
    local desc=$3
    echo -e "${BLUE}[$current/$total]${NC} $desc"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP $current/$total] $desc" >> "$LOG_FILE"
}

# ============ 输入验证函数 ============
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    while true; do
        read -p "$prompt [y/n] (默认: $default): " answer
        answer=${answer:-$default}
        case $answer in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "请输入 y 或 n";;
        esac
    done
}

ask_input() {
    local prompt="$1"
    local default="$2"
    local validator="$3"  # 验证函数名称(可选)

    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt (默认: $default): " input
            input=${input:-$default}
        else
            read -p "$prompt: " input
        fi

        # 如果提供了验证函数,则验证
        if [ -n "$validator" ] && type "$validator" &>/dev/null; then
            if $validator "$input"; then
                echo "$input"
                return 0
            else
                log_error "输入无效,请重试"
                continue
            fi
        fi

        # 不能为空
        if [ -n "$input" ]; then
            echo "$input"
            return 0
        fi
        log_error "输入不能为空"
    done
}

# ============ 验证器函数 ============
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_username() {
    local username=$1
    if [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]] && [ ${#username} -le 32 ]; then
        return 0
    fi
    return 1
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# ============ 系统信息函数 ============
get_server_ip() {
    local ip=$(curl -s --max-time 5 ipinfo.io/ip)
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}

get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$NAME $VERSION"
    else
        echo "Unknown"
    fi
}

check_root() {
    if [ $EUID -ne 0 ]; then
        log_error "此脚本必须以root权限运行"
        exit 1
    fi
}

# ============ 备份函数 ============
backup_file() {
    local file=$1
    local backup_dir="${2:-/root/vps-tools-backup}"

    if [ ! -f "$file" ]; then
        return 0
    fi

    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/$(basename $file).backup.$(date +%Y%m%d_%H%M%S)"
    cp "$file" "$backup_file"
    log_info "已备份: $file -> $backup_file"
}

# ============ 错误处理 ============
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_num=$2
    log_error "脚本在第 $line_num 行出错,退出码: $exit_code"
}

# ============ Ctrl+C 处理 ============
CTRL_C_COUNT=0
ctrl_c_handler() {
    CTRL_C_COUNT=$((CTRL_C_COUNT+1))
    if [ $CTRL_C_COUNT -eq 1 ]; then
        log_warning "再次按 Ctrl+C 确认退出"
        sleep 2
        CTRL_C_COUNT=0
    else
        log_info "正在退出..."
        exit 130
    fi
}

trap ctrl_c_handler INT

# ============ 进度条 ============
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))

    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%$((width - filled))s" | tr ' ' '-'
    printf "] %d%%" $percentage

    if [ $current -eq $total ]; then
        echo
    fi
}

# ============ 依赖检查 ============
check_command() {
    command -v "$1" &> /dev/null
}

require_command() {
    if ! check_command "$1"; then
        log_error "需要安装 $1"
        return 1
    fi
}

# ============ 服务管理 ============
service_start() {
    local service=$1
    systemctl start "$service"
    systemctl enable "$service"
}

service_stop() {
    local service=$1
    systemctl stop "$service"
}

service_status() {
    local service=$1
    systemctl is-active "$service" &>/dev/null
}
```

### lib/module-loader.sh - 模块加载器

```bash
#!/bin/bash
# lib/module-loader.sh - 模块加载器

MODULES_DIR="$(dirname "$0")/../modules"

# 加载模块
load_module() {
    local category=$1  # init/install/manage
    local name=$2      # docker/ssh-config等

    local module_file="$MODULES_DIR/$category/$name.sh"

    if [ ! -f "$module_file" ]; then
        log_error "模块不存在: $category/$name"
        return 1
    fi

    source "$module_file"
    return 0
}

# 执行模块动作
run_module() {
    local category=$1
    local name=$2
    local action=$3  # install/uninstall/status

    load_module "$category" "$name" || return 1

    # 调用模块的函数
    if type "$action" &>/dev/null; then
        $action
        return $?
    else
        log_error "模块 $category/$name 不支持动作: $action"
        return 1
    fi
}

# 列出所有模块
list_modules() {
    local category=$1

    if [ -z "$category" ]; then
        # 列出所有分类
        for cat_dir in "$MODULES_DIR"/*; do
            if [ -d "$cat_dir" ]; then
                echo "$(basename "$cat_dir"):"
                list_modules "$(basename "$cat_dir")"
                echo
            fi
        done
    else
        # 列出指定分类下的模块
        for module in "$MODULES_DIR/$category"/*.sh; do
            if [ -f "$module" ]; then
                local name=$(basename "$module" .sh)
                # 加载模块获取元数据
                source "$module"
                echo "  - $name: $MODULE_NAME (v$MODULE_VERSION)"
            fi
        done
    fi
}

# 检查模块依赖
check_module_dependencies() {
    local category=$1
    local name=$2

    load_module "$category" "$name" || return 1

    if [ -n "$MODULE_DEPS" ]; then
        log_info "检查依赖: $MODULE_DEPS"
        for dep in $MODULE_DEPS; do
            # 递归检查依赖
            if ! check_module_installed "$dep"; then
                log_warning "依赖 $dep 未安装,是否现在安装?"
                if ask_yes_no "安装 $dep"; then
                    # 查找依赖模块并安装
                    install_dependency "$dep" || return 1
                else
                    return 1
                fi
            fi
        done
    fi

    return 0
}

# 检查模块是否已安装
check_module_installed() {
    local name=$1

    # 尝试从不同分类中查找
    for category in init install manage; do
        local module_file="$MODULES_DIR/$category/$name.sh"
        if [ -f "$module_file" ]; then
            source "$module_file"
            if type check_installed &>/dev/null; then
                check_installed
                return $?
            fi
        fi
    done

    return 1
}

# 安装依赖
install_dependency() {
    local dep=$1

    # 尝试从install分类安装
    if [ -f "$MODULES_DIR/install/$dep.sh" ]; then
        run_module "install" "$dep" "install"
        return $?
    fi

    log_error "未找到依赖模块: $dep"
    return 1
}
```

### lib/menu.sh - 菜单系统

```bash
#!/bin/bash
# lib/menu.sh - 菜单系统

# 显示主菜单
show_main_menu() {
    clear
    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
           ${BOLD}VPS 一体化配置工具 v2.0${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BLUE}系统信息:${NC}
  IP地址: $(get_server_ip)
  系统: $(get_os_info)
  用户: $(whoami)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${GREEN}[系统初始化]${NC}
  1. 🚀 一键初始化VPS (推荐新服务器)
  2. 📦 更新系统
  3. 👤 创建用户
  4. 🔐 配置SSH安全
  5. 🛡️  配置Fail2Ban
  6. 🔥 配置防火墙
  7. 🔒 系统安全加固

${BLUE}[应用安装]${NC}
  11. 🎯 一键安装全部应用
  12. 🐳 安装Docker
  13. 🌐 安装Nginx Proxy Manager
  14. 📡 安装s-ui

${YELLOW}[系统管理]${NC}
  21. 📊 查看服务状态
  22. 💾 备份配置
  23. 🗑️  卸载应用
  24. 📋 查看日志

${NC}[高级选项]${NC}
  31. ⚙️  使用预设配置
  32. 📤 导出当前配置

  0. 👋 退出
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# 读取用户选择
read_menu_choice() {
    read -p "请输入选项 [0-32]: " choice
    echo "$choice"
}

# 等待用户按键继续
press_any_key() {
    read -n 1 -s -r -p "按任意键继续..."
    echo
}

# 确认危险操作
confirm_dangerous_action() {
    local action=$1
    log_warning "⚠️  警告: 即将执行 $action"
    ask_yes_no "确定要继续吗?"
}
```

## 主入口脚本设计

### vps-tool.sh

```bash
#!/bin/bash
# vps-tool.sh - VPS一体化配置工具主入口

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载核心库
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/menu.sh"
source "$SCRIPT_DIR/lib/module-loader.sh"

# 检查root权限
check_root

# 创建必要目录
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/backup"

# 主循环
main_loop() {
    while true; do
        show_main_menu
        choice=$(read_menu_choice)

        case $choice in
            0)
                log_info "退出程序"
                exit 0
                ;;
            1)
                # 一键初始化VPS
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
            11)
                # 一键安装全部应用
                run_install_all
                ;;
            12)
                run_module "install" "docker" "install"
                ;;
            13)
                run_module "install" "nginx-proxy-manager" "install"
                ;;
            14)
                run_module "install" "s-ui" "install"
                ;;
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
            31)
                run_preset_config
                ;;
            32)
                export_config
                ;;
            *)
                log_error "无效选项: $choice"
                ;;
        esac

        press_any_key
    done
}

# 一键初始化VPS
run_init_all() {
    log_info "开始一键初始化VPS..."

    local modules=(
        "01-system-update"
        "02-create-user"
        "03-ssh-config"
        "04-fail2ban"
        "05-firewall"
        "06-security-hardening"
    )

    local total=${#modules[@]}
    local current=0

    for module in "${modules[@]}"; do
        current=$((current + 1))
        log_step $current $total "执行模块: $module"

        if ! run_module "init" "$module" "install"; then
            log_error "模块 $module 执行失败"
            ask_yes_no "是否继续?" || return 1
        fi
    done

    log_success "VPS初始化完成!"
}

# 一键安装全部应用
run_install_all() {
    log_info "开始一键安装全部应用..."

    local modules=(
        "docker"
        "nginx-proxy-manager"
        "s-ui"
    )

    for module in "${modules[@]}"; do
        if ! run_module "install" "$module" "install"; then
            log_error "模块 $module 安装失败"
            ask_yes_no "是否继续安装其他应用?" || return 1
        fi
    done

    log_success "全部应用安装完成!"
}

# 显示状态
show_status() {
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "           服务状态"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 检查各个模块状态
    for category in init install; do
        for module in "$MODULES_DIR/$category"/*.sh; do
            if [ -f "$module" ]; then
                local name=$(basename "$module" .sh)
                source "$module"
                if type status &>/dev/null; then
                    status
                fi
            fi
        done
    done
}

# 卸载菜单
run_uninstall_menu() {
    clear
    echo "选择要卸载的应用:"
    echo "  1. Docker"
    echo "  2. Nginx Proxy Manager"
    echo "  3. s-ui"
    echo "  0. 返回"

    read -p "请选择: " choice

    case $choice in
        1) run_module "install" "docker" "uninstall" ;;
        2) run_module "install" "nginx-proxy-manager" "uninstall" ;;
        3) run_module "install" "s-ui" "uninstall" ;;
        0) return ;;
        *) log_error "无效选项" ;;
    esac
}

# 启动主循环
main_loop
```

## 关键模块示例

### modules/install/nginx-proxy-manager.sh (修复后的NPM安装)

```bash
#!/bin/bash
# modules/install/nginx-proxy-manager.sh

MODULE_NAME="Nginx Proxy Manager"
MODULE_VERSION="1.0.0"
MODULE_DEPS="docker"
MODULE_CATEGORY="install"

NPM_DIR="/opt/npm"

check_installed() {
    [ -f "$NPM_DIR/installed.flag" ]
}

install() {
    log_info "开始安装 $MODULE_NAME..."

    # 检查依赖
    if ! check_module_installed "docker"; then
        log_error "需要先安装Docker"
        ask_yes_no "是否现在安装Docker?" && run_module "install" "docker" "install" || return 1
    fi

    # 检查是否已安装
    if check_installed; then
        log_warning "$MODULE_NAME 已安装"
        ask_yes_no "是否重新安装?" || return 0
    fi

    # 步骤1: 创建目录
    log_step 1 5 "创建目录"
    mkdir -p "$NPM_DIR"/{data,letsencrypt} || return 1
    cd "$NPM_DIR" || return 1

    # 步骤2: 创建docker-compose.yml (修复网络模式!)
    log_step 2 5 "创建配置文件"
    cat > docker-compose.yml << 'EOF'
version: "3.8"
services:
  app:
    image: "jc21/nginx-proxy-manager:latest"
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
    networks:
      - npm_network

networks:
  npm_network:
    driver: bridge
EOF

    # 步骤3: 启动服务
    log_step 3 5 "启动服务"
    if ! docker compose up -d; then
        log_error "启动失败"
        return 1
    fi

    # 步骤4: 等待服务启动
    log_step 4 5 "等待服务启动"
    sleep 10

    # 步骤5: 验证安装
    log_step 5 5 "验证安装"
    if docker ps | grep -q nginx-proxy-manager; then
        touch "$NPM_DIR/installed.flag"
        log_success "$MODULE_NAME 安装成功!"
        show_post_install_info
        return 0
    else
        log_error "服务未正常启动"
        docker compose logs
        return 1
    fi
}

uninstall() {
    log_info "开始卸载 $MODULE_NAME..."

    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    cd "$NPM_DIR" || return 1

    # 停止服务
    log_info "停止服务..."
    docker compose down

    # 询问是否保留数据
    if ask_yes_no "是否保留数据?"; then
        local backup_dir="$NPM_DIR.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$NPM_DIR" "$backup_dir"
        log_info "数据已备份到: $backup_dir"
    else
        rm -rf "$NPM_DIR"
        log_info "已删除所有数据"
    fi

    log_success "$MODULE_NAME 卸载完成"
}

status() {
    if check_installed; then
        echo -e "${GREEN}✓${NC} $MODULE_NAME: 已安装"
        if docker ps | grep -q nginx-proxy-manager; then
            echo "  状态: 运行中"
            echo "  端口: 80, 81, 443"
        else
            echo "  状态: 已停止"
        fi
    else
        echo -e "${RED}✗${NC} $MODULE_NAME: 未安装"
    fi
}

show_post_install_info() {
    local ip=$(get_server_ip)
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${GREEN}Nginx Proxy Manager 安装完成!${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${BOLD}访问信息:${NC}
  管理面板: http://$ip:81
  HTTP端口: 80
  HTTPS端口: 443

${BOLD}默认凭据:${NC}
  邮箱: admin@example.com
  密码: changeme

${YELLOW}重要提示:${NC}
  1. 请立即登录并修改默认密码!
  2. 建议配置SSL证书
  3. 确保防火墙已开放 80, 81, 443 端口

${BOLD}管理命令:${NC}
  启动: docker compose -f $NPM_DIR/docker-compose.yml up -d
  停止: docker compose -f $NPM_DIR/docker-compose.yml down
  重启: docker compose -f $NPM_DIR/docker-compose.yml restart
  日志: docker compose -f $NPM_DIR/docker-compose.yml logs -f
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}
EOF
}
```

## 配置预设示例

### config/presets/standard.conf

```bash
# VPS工具标准配置预设
# 使用方法: ./vps-tool.sh --preset standard

# 系统配置
SYSTEM_UPDATE=yes
SYSTEM_TIMEZONE="Asia/Shanghai"
SYSTEM_AUTO_UPDATE=yes

# 用户配置
CREATE_USER=yes
USERNAME="admin"
USER_GROUPS="sudo,docker"

# SSH配置
CONFIGURE_SSH=yes
SSH_PORT=22222
SSH_PASSWORD_AUTH=no
SSH_ROOT_LOGIN=no
SSH_MAX_AUTH_TRIES=3

# Fail2Ban配置
CONFIGURE_FAIL2BAN=yes
FAIL2BAN_BANTIME=3600
FAIL2BAN_MAXRETRY=3

# 防火墙配置
CONFIGURE_FIREWALL=yes
FIREWALL_ALLOW_PORTS="80,443,81,22222"

# 应用安装
INSTALL_DOCKER=yes
INSTALL_NPM=yes
INSTALL_SUI=no

# 安全加固
SECURITY_HARDENING=yes
DISABLE_IPV6=no
KERNEL_HARDENING=yes
```

## 添加新模块的步骤

### 例如:添加Caddy服务器安装

1. 创建模块文件: `modules/install/caddy.sh`
2. 按照标准模块结构编写:
   - 定义元数据 (MODULE_NAME, MODULE_DEPS等)
   - 实现 check_installed()
   - 实现 install()
   - 实现 uninstall()
   - 实现 status()
   - 实现 show_post_install_info()

3. 在主菜单添加选项:
   ```bash
   # vps-tool.sh
   15. 安装Caddy
   ...
   15)
       run_module "install" "caddy" "install"
       ;;
   ```

4. 完成!模块自动集成到系统中

## 优势总结

1. **统一入口**: 只需执行 `./vps-tool.sh`
2. **模块化**: 每个功能独立,互不影响
3. **易扩展**: 添加新功能只需创建新模块文件
4. **依赖管理**: 自动检查并安装依赖
5. **错误处理**: 统一的错误处理和回滚
6. **状态跟踪**: 清晰的安装状态管理
7. **日志记录**: 所有操作记录到日志
8. **交互友好**: 彩色输出、进度显示
9. **安全优先**: 修复所有已知安全问题
10. **预设支持**: 支持非交互批量部署

## 实施步骤

1. **阶段1**: 创建核心库和目录结构
2. **阶段2**: 迁移现有功能到模块
3. **阶段3**: 修复安全问题
4. **阶段4**: 添加高级功能
5. **阶段5**: 测试和文档
