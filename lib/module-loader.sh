#!/bin/bash
# lib/module-loader.sh - 模块加载器
# 负责动态加载、执行和管理所有功能模块

# 加载依赖
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MODULES_DIR="$SCRIPT_DIR/modules"

# ============ 模块加载 ============
load_module() {
    local category=$1  # init/install/manage
    local name=$2      # docker/ssh-config等

    local module_file="$MODULES_DIR/$category/$name.sh"

    if [ ! -f "$module_file" ]; then
        log_error "模块不存在: $category/$name"
        log_debug "查找路径: $module_file"
        return 1
    fi

    log_debug "加载模块: $category/$name"

    # source 模块文件
    # shellcheck source=/dev/null
    source "$module_file"
    return 0
}

# ============ 执行模块动作 ============
run_module() {
    local category=$1
    local name=$2
    local action=$3  # install/uninstall/status

    log_debug "运行模块: $category/$name ($action)"

    # 加载模块
    load_module "$category" "$name" || return 1

    # 检查函数是否存在
    if ! type "$action" &>/dev/null; then
        log_error "模块 $category/$name 不支持动作: $action"
        return 1
    fi

    # 执行前检查依赖
    if [ "$action" = "install" ] && type "check_dependencies" &>/dev/null; then
        if ! check_dependencies; then
            log_error "依赖检查失败"
            return 1
        fi
    fi

    # 执行动作
    log_info "执行: $MODULE_NAME - $action"
    $action
    local result=$?

    if [ $result -eq 0 ]; then
        log_success "$MODULE_NAME $action 完成"
    else
        log_error "$MODULE_NAME $action 失败 (退出码: $result)"
    fi

    return $result
}

# ============ 列出所有模块 ============
list_modules() {
    local category=$1

    if [ -z "$category" ]; then
        # 列出所有分类
        echo -e "${BOLD}可用模块:${NC}"
        echo
        for cat_dir in "$MODULES_DIR"/*; do
            if [ -d "$cat_dir" ]; then
                local cat_name=$(basename "$cat_dir")
                echo -e "${CYAN}[$cat_name]${NC}"
                list_modules "$cat_name"
                echo
            fi
        done
    else
        # 列出指定分类下的模块
        if [ ! -d "$MODULES_DIR/$category" ]; then
            log_error "分类不存在: $category"
            return 1
        fi

        for module in "$MODULES_DIR/$category"/*.sh; do
            if [ -f "$module" ]; then
                local name=$(basename "$module" .sh)
                # 加载模块获取元数据
                (
                    # shellcheck source=/dev/null
                    source "$module"
                    if [ -n "$MODULE_NAME" ]; then
                        printf "  ${GREEN}%-25s${NC} %s (v%s)\n" "$name" "$MODULE_NAME" "${MODULE_VERSION:-1.0.0}"
                    else
                        printf "  ${YELLOW}%-25s${NC} %s\n" "$name" "(无元数据)"
                    fi
                )
            fi
        done
    fi
}

# ============ 检查模块依赖 ============
check_module_dependencies() {
    local category=$1
    local name=$2

    load_module "$category" "$name" || return 1

    if [ -z "$MODULE_DEPS" ]; then
        log_debug "模块 $name 无依赖"
        return 0
    fi

    log_info "检查依赖: $MODULE_DEPS"

    for dep in $MODULE_DEPS; do
        log_debug "检查依赖: $dep"

        # 检查依赖是否已安装
        if ! check_module_installed "$dep"; then
            log_warning "依赖 $dep 未安装"

            if ask_yes_no "是否现在安装 $dep?"; then
                # 安装依赖
                if ! install_dependency "$dep"; then
                    log_error "依赖 $dep 安装失败"
                    return 1
                fi
            else
                log_error "缺少依赖: $dep"
                return 1
            fi
        else
            log_debug "依赖 $dep 已安装"
        fi
    done

    return 0
}

# ============ 检查模块是否已安装 ============
check_module_installed() {
    local name=$1

    log_debug "检查模块是否已安装: $name"

    # 尝试从不同分类中查找模块
    for category in init install manage; do
        local module_file="$MODULES_DIR/$category/$name.sh"

        if [ -f "$module_file" ]; then
            # 在子shell中加载模块并检查
            (
                # shellcheck source=/dev/null
                source "$module_file"

                if type check_installed &>/dev/null; then
                    check_installed
                    exit $?
                else
                    # 没有 check_installed 函数,假设未安装
                    exit 1
                fi
            )
            return $?
        fi
    done

    # 模块文件不存在
    log_debug "模块文件不存在: $name"
    return 1
}

# ============ 安装依赖 ============
install_dependency() {
    local dep=$1

    log_info "安装依赖: $dep"

    # 尝试从 install 分类安装
    if [ -f "$MODULES_DIR/install/$dep.sh" ]; then
        run_module "install" "$dep" "install"
        return $?
    fi

    # 尝试从 init 分类安装
    if [ -f "$MODULES_DIR/init/$dep.sh" ]; then
        run_module "init" "$dep" "install"
        return $?
    fi

    log_error "未找到依赖模块: $dep"
    return 1
}

# ============ 批量执行模块 ============
run_modules_batch() {
    local category=$1
    shift
    local modules=("$@")

    local total=${#modules[@]}
    local current=0
    local failed=()

    for module in "${modules[@]}"; do
        current=$((current + 1))
        echo
        log_step $current $total "执行模块: $module"

        if ! run_module "$category" "$module" "install"; then
            log_error "模块 $module 执行失败"
            failed+=("$module")

            if ! ask_yes_no "是否继续执行其他模块?"; then
                log_warning "批量执行已取消"
                return 1
            fi
        fi
    done

    echo
    if [ ${#failed[@]} -eq 0 ]; then
        log_success "所有模块执行成功!"
        return 0
    else
        log_warning "以下模块执行失败: ${failed[*]}"
        return 1
    fi
}

# ============ 获取模块信息 ============
get_module_info() {
    local category=$1
    local name=$2
    local field=$3  # name/version/deps/category

    local module_file="$MODULES_DIR/$category/$name.sh"

    if [ ! -f "$module_file" ]; then
        return 1
    fi

    (
        # shellcheck source=/dev/null
        source "$module_file"

        case $field in
            name)
                echo "${MODULE_NAME:-未知}"
                ;;
            version)
                echo "${MODULE_VERSION:-1.0.0}"
                ;;
            deps)
                echo "${MODULE_DEPS:-}"
                ;;
            category)
                echo "${MODULE_CATEGORY:-$category}"
                ;;
            desc)
                echo "${MODULE_DESC:-无描述}"
                ;;
            *)
                echo ""
                ;;
        esac
    )
}

# ============ 验证模块完整性 ============
validate_module() {
    local category=$1
    local name=$2

    local module_file="$MODULES_DIR/$category/$name.sh"

    if [ ! -f "$module_file" ]; then
        log_error "模块文件不存在: $module_file"
        return 1
    fi

    log_info "验证模块: $category/$name"

    # 检查必需函数
    local required_functions=("install" "check_installed")
    local optional_functions=("uninstall" "status" "check_dependencies")

    local has_error=false

    (
        # shellcheck source=/dev/null
        source "$module_file"

        # 检查元数据
        if [ -z "$MODULE_NAME" ]; then
            echo "  ⚠ 缺少 MODULE_NAME"
            has_error=true
        fi

        # 检查必需函数
        for func in "${required_functions[@]}"; do
            if ! type "$func" &>/dev/null; then
                echo "  ✗ 缺少必需函数: $func"
                has_error=true
            else
                echo "  ✓ $func"
            fi
        done

        # 检查可选函数
        for func in "${optional_functions[@]}"; do
            if type "$func" &>/dev/null; then
                echo "  ✓ $func (可选)"
            else
                echo "  - $func (可选,未定义)"
            fi
        done

        if [ "$has_error" = true ]; then
            exit 1
        fi
    )

    return $?
}

# ============ 查找模块 ============
find_module() {
    local name=$1

    # 搜索所有分类
    for category in init install manage; do
        if [ -f "$MODULES_DIR/$category/$name.sh" ]; then
            echo "$category"
            return 0
        fi
    done

    return 1
}

# ============ 获取所有已安装模块 ============
get_installed_modules() {
    local category=${1:-}

    local categories
    if [ -n "$category" ]; then
        categories=("$category")
    else
        categories=(init install manage)
    fi

    for cat in "${categories[@]}"; do
        if [ ! -d "$MODULES_DIR/$cat" ]; then
            continue
        fi

        for module in "$MODULES_DIR/$cat"/*.sh; do
            if [ -f "$module" ]; then
                local name=$(basename "$module" .sh)

                if check_module_installed "$name"; then
                    echo "$cat/$name"
                fi
            fi
        done
    done
}

# ============ 卸载模块 ============
uninstall_module() {
    local category=$1
    local name=$2

    log_info "卸载模块: $category/$name"

    # 加载模块
    load_module "$category" "$name" || return 1

    # 检查是否已安装
    if ! check_installed; then
        log_warning "$MODULE_NAME 未安装"
        return 0
    fi

    # 确认卸载
    if ! confirm_action "卸载 $MODULE_NAME" "此操作可能删除数据"; then
        log_info "已取消卸载"
        return 1
    fi

    # 执行卸载
    if type uninstall &>/dev/null; then
        uninstall
        return $?
    else
        log_error "模块不支持卸载功能"
        return 1
    fi
}

# ============ 重新安装模块 ============
reinstall_module() {
    local category=$1
    local name=$2

    log_info "重新安装模块: $category/$name"

    # 先卸载
    if check_module_installed "$name"; then
        uninstall_module "$category" "$name" || {
            log_error "卸载失败,取消重新安装"
            return 1
        }
    fi

    # 再安装
    run_module "$category" "$name" "install"
}

# ============ 显示所有模块状态 ============
show_all_modules_status() {
    echo
    print_header "模块状态"
    echo

    for category in init install; do
        echo -e "${BOLD}[$category]${NC}"

        if [ ! -d "$MODULES_DIR/$category" ]; then
            echo "  (无模块)"
            echo
            continue
        fi

        for module in "$MODULES_DIR/$category"/*.sh; do
            if [ -f "$module" ]; then
                local name=$(basename "$module" .sh)

                # 在子shell中执行状态检查
                (
                    # shellcheck source=/dev/null
                    source "$module"

                    if type status &>/dev/null; then
                        status
                    else
                        if type check_installed &>/dev/null && check_installed; then
                            echo -e "  ${GREEN}✓${NC} $MODULE_NAME: 已安装"
                        else
                            echo -e "  ${RED}✗${NC} $MODULE_NAME: 未安装"
                        fi
                    fi
                )
            fi
        done
        echo
    done
}

# ============ 导出函数供其他脚本使用 ============
