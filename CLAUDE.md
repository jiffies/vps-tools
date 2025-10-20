# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

**VPS一体化配置工具 v2.0** - 模块化、安全的VPS初始化和应用安装系统。

这是一个完全重构的模块化系统,将原有的两个脚本(initVPS.sh, installApp.sh)整合为统一的工具,采用模块化架构,方便扩展和维护。

## 核心架构

### 主入口: vps-tool.sh
唯一需要执行的脚本,提供交互式菜单和命令行模式。

### 核心库(lib/)
- **common.sh**: 通用函数库(日志、颜色、输入验证、系统信息、备份等)
- **menu.sh**: 菜单系统(主菜单、子菜单、对话框、进度显示等)
- **module-loader.sh**: 模块加载器(加载、执行、管理模块,依赖处理)

### 模块系统(modules/)
每个功能都是独立模块:

**初始化模块(init/):**
- 01-system-update.sh - 系统更新
- 02-create-user.sh - 创建用户
- 03-ssh-config.sh - SSH安全配置
- 04-fail2ban.sh - Fail2Ban配置
- 05-firewall.sh - 防火墙配置
- 06-security-hardening.sh - 系统加固

**安装模块(install/):**
- docker.sh - Docker + Compose V2
- nginx-proxy-manager.sh - NPM(已修复安全问题)
- 3x-ui.sh - 3x-ui面板

## 模块开发规范

### 标准模块结构

```bash
#!/bin/bash
# modules/{category}/{name}.sh

# 元数据
MODULE_NAME="显示名称"
MODULE_VERSION="1.0.0"
MODULE_DEPS="依赖的模块,空格分隔"
MODULE_CATEGORY="init/install/manage"

# 必需函数
check_installed() { }  # 检查是否已安装
install() { }          # 安装逻辑

# 可选函数
uninstall() { }        # 卸载逻辑
status() { }           # 状态显示
check_dependencies() { } # 额外依赖检查
show_post_install_info() { } # 安装后信息
```

### 编码规范

1. **使用公共函数库**
   ```bash
   log_info "信息"
   log_success "成功"
   log_error "错误"
   log_warning "警告"
   log_step 1 5 "步骤描述"
   ```

2. **用户交互**
   ```bash
   ask_yes_no "是否继续?"
   ask_input "请输入" "默认值" "验证函数"
   ```

3. **错误处理**
   ```bash
   if ! command; then
       log_error "失败"
       return 1
   fi
   ```

4. **安装标记**
   ```bash
   INSTALL_FLAG="/path/to/flag"
   touch "$INSTALL_FLAG"
   ```

## 已修复的安全问题

### P0 - 严重安全问题(已修复)

1. **NPM网络模式安全漏洞**
   - 原: `network_mode: host` (暴露宿主机所有端口)
   - 改: 桥接网络 + 明确端口映射
   - 文件: modules/install/nginx-proxy-manager.sh:941-961

2. **Docker GPG密钥下载安全**
   - 确保使用HTTPS
   - 文件: modules/install/docker.sh:54-61

3. **完整的错误检查和回滚**
   - 所有模块包含错误检查
   - 安装失败自动清理

## 添加新模块

### 步骤1: 复制模板
```bash
cp modules/MODULE_TEMPLATE.sh modules/install/新模块.sh
```

### 步骤2: 修改元数据和实现函数
编辑新模块文件,填写元数据,实现必需函数。

### 步骤3: 在主菜单添加入口
编辑 vps-tool.sh,在菜单中添加选项和case分支。

### 步骤4: 测试
```bash
# 直接测试模块
./modules/install/新模块.sh install

# 通过主程序测试
./vps-tool.sh
```

## 关键设计决策

1. **模块化架构**: 每个功能独立,互不干扰,易于维护
2. **依赖自动管理**: module-loader自动检查和安装依赖
3. **统一错误处理**: 所有模块使用相同的错误处理机制
4. **配置备份**: 修改前自动备份,失败自动恢复
5. **日志记录**: 所有操作记录到 logs/vps-tools.log

## 常用开发命令

```bash
# 列出所有模块
./vps-tool.sh --list

# 查看模块状态
./vps-tool.sh --status

# 验证模块完整性
source lib/module-loader.sh
validate_module install docker

# 查看日志
tail -f logs/vps-tools.log
```

## 注意事项

1. **不要在本地执行**: 这些脚本设计用于在VPS上执行
2. **需要root权限**: 大部分操作需要root权限
3. **保留原脚本**: initVPS.sh和installApp.sh保留作为参考
4. **模块独立运行**: 每个模块可以独立执行,也可以通过主程序调用
5. **错误不退出**: 使用 set +e,手动控制错误处理

## 测试和部署

### 本地开发
在本地编辑代码,使用git管理版本。

### 部署到VPS
```bash
# 方法1: Git克隆
cd /root
git clone <repo> vps-tools
cd vps-tools
chmod +x vps-tool.sh

# 方法2: 直接上传
scp -r vps-tools/ root@vps:/root/
```

### 测试流程
1. 在测试VPS上测试新模块
2. 验证安装/卸载/状态功能
3. 检查日志输出
4. 确认错误处理
5. 提交代码

## 文件说明

| 文件 | 说明 |
|------|------|
| vps-tool.sh | 主入口脚本 |
| lib/common.sh | 通用函数库(450+行) |
| lib/menu.sh | 菜单系统 |
| lib/module-loader.sh | 模块加载器 |
| modules/MODULE_TEMPLATE.sh | 模块开发模板 |
| modules/install/*.sh | 安装模块 |
| modules/init/*.sh | 初始化模块 |
| README.md | 用户文档 |
| PLAN.md | 设计方案和安全分析 |
| CLAUDE.md | 本文档 |

## 未来扩展

- [ ] 完成所有init模块(SSH、Fail2Ban、防火墙、安全加固)
- [ ] 添加更多install模块(Caddy、PostgreSQL等)
- [ ] 支持配置预设(非交互模式)
- [ ] Web UI界面
- [ ] 多服务器管理
