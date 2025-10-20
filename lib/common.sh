#!/bin/bash
# lib/common.sh - 通用函数库
# VPS工具核心库,提供日志、输入验证、系统信息等通用功能

# ============ 颜色定义 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ============ 全局变量 ============
LOG_FILE="${LOG_FILE:-/var/log/vps-tools.log}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============ 日志函数 ============
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_step() {
    local current=$1
    local total=$2
    local desc=$3
    echo -e "${CYAN}[步骤 $current/$total]${NC} $desc"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP $current/$total] $desc" >> "$LOG_FILE" 2>/dev/null || true
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# ============ 输入验证函数 ============
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    while true; do
        if [ "$default" = "y" ]; then
            read -p "$prompt [Y/n]: " answer
        else
            read -p "$prompt [y/N]: " answer
        fi
        answer=${answer:-$default}
        case ${answer,,} in
            y|yes ) return 0;;
            n|no ) return 1;;
            * ) echo "请输入 y 或 n";;
        esac
    done
}

ask_input() {
    local prompt="$1"
    local default="$2"
    local validator="$3"

    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt (默认: $default): " input
            input=${input:-$default}
        else
            read -p "$prompt: " input
        fi

        # 验证非空
        if [ -z "$input" ]; then
            log_error "输入不能为空"
            continue
        fi

        # 如果提供了验证函数
        if [ -n "$validator" ] && type "$validator" &>/dev/null; then
            if $validator "$input"; then
                echo "$input"
                return 0
            else
                log_error "输入无效,请重试"
                continue
            fi
        fi

        echo "$input"
        return 0
    done
}

# ============ 验证器函数 ============
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    log_error "端口必须在 1-65535 之间"
    return 1
}

validate_username() {
    local username=$1
    if [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]] && [ ${#username} -le 32 ]; then
        return 0
    fi
    log_error "用户名必须以小写字母或下划线开头,只能包含小写字母、数字、下划线、连字符"
    return 1
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                log_error "IP地址格式错误"
                return 1
            fi
        done
        return 0
    fi
    log_error "IP地址格式错误"
    return 1
}

validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    log_error "邮箱格式错误"
    return 1
}

# ============ 系统信息函数 ============
get_server_ip() {
    local ip
    # 尝试从多个源获取IP
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    if [ -z "$ip" ]; then
        ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null)
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null)
    fi
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "${ip:-未知}"
}

get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$NAME $VERSION"
    else
        echo "Unknown"
    fi
}

get_system_timezone() {
    if [ -f /etc/timezone ]; then
        cat /etc/timezone
    else
        timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC"
    fi
}

get_total_memory() {
    free -h | awk '/^Mem:/ {print $2}'
}

get_disk_usage() {
    df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}'
}

# ============ 权限检查 ============
check_root() {
    if [ $EUID -ne 0 ]; then
        log_error "此脚本必须以root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

ensure_root() {
    check_root
}

# ============ 备份函数 ============
backup_file() {
    local file=$1
    local backup_dir="${2:-$SCRIPT_DIR/backup}"

    if [ ! -f "$file" ]; then
        log_debug "文件不存在,无需备份: $file"
        return 0
    fi

    mkdir -p "$backup_dir"
    local filename=$(basename "$file")
    local backup_file="$backup_dir/${filename}.backup.$(date +%Y%m%d_%H%M%S)"

    if cp -p "$file" "$backup_file" 2>/dev/null; then
        log_info "已备份: $file -> $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "备份失败: $file"
        return 1
    fi
}

restore_file() {
    local backup_file=$1
    local target=$2

    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi

    if cp -p "$backup_file" "$target" 2>/dev/null; then
        log_success "已恢复: $target"
        return 0
    else
        log_error "恢复失败: $target"
        return 1
    fi
}

# ============ 错误处理 ============
# 不使用 set -e,因为我们要自己控制错误处理
set +e

error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "$msg"
    exit "$code"
}

# ============ Ctrl+C 处理 ============
CTRL_C_COUNT=0
ctrl_c_handler() {
    CTRL_C_COUNT=$((CTRL_C_COUNT + 1))
    if [ $CTRL_C_COUNT -eq 1 ]; then
        echo
        log_warning "再次按 Ctrl+C 确认退出"
        sleep 2
        CTRL_C_COUNT=0
    else
        echo
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
    printf "] %d%%" "$percentage"

    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# ============ 依赖检查 ============
check_command() {
    command -v "$1" &> /dev/null
}

require_command() {
    local cmd=$1
    local package=${2:-$1}

    if ! check_command "$cmd"; then
        log_error "需要安装 $cmd"
        if ask_yes_no "是否现在安装 $package?"; then
            apt-get update -qq
            apt-get install -y "$package"
            return $?
        else
            return 1
        fi
    fi
    return 0
}

check_package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# ============ 服务管理 ============
service_start() {
    local service=$1
    log_info "启动服务: $service"
    systemctl start "$service"
    systemctl enable "$service"
}

service_stop() {
    local service=$1
    log_info "停止服务: $service"
    systemctl stop "$service"
}

service_restart() {
    local service=$1
    log_info "重启服务: $service"
    systemctl restart "$service"
}

service_status() {
    local service=$1
    systemctl is-active --quiet "$service"
}

service_enabled() {
    local service=$1
    systemctl is-enabled --quiet "$service"
}

# ============ 网络工具 ============
check_internet() {
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null || ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        return 0
    else
        log_error "无法连接到互联网"
        return 1
    fi
}

wait_for_port() {
    local host=${1:-localhost}
    local port=$2
    local timeout=${3:-30}
    local elapsed=0

    log_info "等待端口 $host:$port 可用..."

    while [ $elapsed -lt $timeout ]; do
        if timeout 1 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            log_success "端口 $port 已就绪"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    log_error "端口 $port 超时未就绪"
    return 1
}

# ============ 文件操作 ============
safe_write() {
    local file=$1
    local content=$2
    local backup_first=${3:-true}

    # 备份原文件
    if [ "$backup_first" = "true" ] && [ -f "$file" ]; then
        backup_file "$file" || return 1
    fi

    # 写入临时文件
    local tmpfile="${file}.tmp.$$"
    echo "$content" > "$tmpfile" || return 1

    # 移动到目标位置
    mv "$tmpfile" "$file" || return 1

    log_debug "已写入文件: $file"
    return 0
}

# ============ 分隔线和格式化 ============
print_separator() {
    local char="${1:-━}"
    local width="${2:-60}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

print_header() {
    local text="$1"
    local width=60
    echo
    print_separator "━" $width
    printf "${BOLD}%*s${NC}\n" $(( (${#text} + width) / 2)) "$text"
    print_separator "━" $width
}

print_box() {
    local text="$1"
    local color="${2:-$BLUE}"
    echo
    echo -e "${color}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${color}│${NC} $text"
    echo -e "${color}└─────────────────────────────────────────────┘${NC}"
}

# ============ 实用工具 ============
generate_random_password() {
    local length=${1:-16}
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
}

is_valid_domain() {
    local domain=$1
    [[ $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]
}

# ============ 初始化日志 ============
init_log() {
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || LOG_FILE="/tmp/vps-tools.log"
    fi

    # 测试写入权限
    if ! touch "$LOG_FILE" 2>/dev/null; then
        LOG_FILE="/tmp/vps-tools.log"
    fi

    log_debug "日志文件: $LOG_FILE"
}

# 自动初始化日志
init_log

# ============ 导出函数供其他脚本使用 ============
# 当其他脚本 source 这个文件时,所有函数都可用
