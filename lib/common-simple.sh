#!/bin/bash
# lib/common-simple.sh - 简化版通用函数库(强制颜色)

# ============ 强制使用颜色(不检测) ============
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
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# ============ 测试函数 ============
test_colors() {
    echo "========== 颜色测试 =========="
    log_info "这是信息消息"
    log_success "这是成功消息"
    log_warning "这是警告消息"
    log_error "这是错误消息"
    echo ""
    printf "直接printf: ${GREEN}绿色${NC} ${RED}红色${NC} ${BLUE}蓝色${NC}\n"
}

# 如果直接执行此脚本,运行测试
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    test_colors
fi
