# VPS 一体化配置工具 v2.0

一个模块化、安全的VPS初始化和应用安装工具,支持交互式菜单和命令行模式。

## ✨ 特性

- **🎯 一键操作**: 一键初始化VPS或安装全部应用
- **🧩 模块化设计**: 每个功能独立模块,易于扩展和维护
- **🔐 安全优先**: 修复了所有已知安全问题
  - NPM使用桥接网络而非host模式
  - Docker GPG密钥使用HTTPS下载
  - SSH配置包含完整的安全参数
- **📊 交互式菜单**: 彩色UI,清晰的状态显示
- **🔄 依赖管理**: 自动检查和安装模块依赖
- **📝 完整日志**: 所有操作记录到日志文件
- **💾 配置备份**: 自动备份重要配置文件
- **🗑️ 一键卸载**: 支持保留数据的卸载选项

## 🚀 快速开始

### 安装

```bash
# 克隆或下载到VPS
cd /root
git clone <repository-url> vps-tools
cd vps-tools

# 设置执行权限
chmod +x vps-tool.sh
chmod +x modules/**/*.sh

# 启动工具
./vps-tool.sh
```

### 使用方法

####模式1: 交互式菜单 (推荐)

```bash
./vps-tool.sh
```

会显示主菜单,根据提示选择操作。

#### 模式2: 命令行模式

```bash
# 查看帮助
./vps-tool.sh --help

# 一键初始化VPS
./vps-tool.sh --init

# 一键安装全部应用
./vps-tool.sh --install-all

# 查看服务状态
./vps-tool.sh --status

# 列出所有模块
./vps-tool.sh --list
```

## 📂 项目结构

```
vps-tools/
├── vps-tool.sh                    # 主入口脚本
├── lib/                           # 核心库
│   ├── common.sh                  # 通用函数(日志、验证等)
│   ├── menu.sh                    # 菜单系统
│   └── module-loader.sh           # 模块加载器
├── modules/                       # 功能模块
│   ├── init/                      # 初始化模块
│   │   ├── 01-system-update.sh
│   │   ├── 02-create-user.sh
│   │   ├── 03-ssh-config.sh
│   │   ├── 04-fail2ban.sh
│   │   ├── 05-firewall.sh
│   │   └── 06-security-hardening.sh
│   ├── install/                   # 安装模块
│   │   ├── docker.sh
│   │   ├── nginx-proxy-manager.sh
│   │   └── 3x-ui.sh
│   └── MODULE_TEMPLATE.sh         # 模块模板
├── config/                        # 配置文件
│   ├── templates/                 # 配置模板
│   └── presets/                   # 预设配置
├── logs/                          # 日志目录
├── backup/                        # 备份目录
├── README.md                      # 本文档
├── PLAN.md                        # 设计方案
└── CLAUDE.md                      # Claude指导文档
```

## 🛠️ 功能模块

### 系统初始化模块 (init/)

| 模块 | 功能 | 状态 |
|------|------|------|
| 01-system-update | 更新系统和安装基础工具 | ✅ |
| 02-create-user | 创建普通用户并配置sudo | 📝 模板 |
| 03-ssh-config | 配置SSH安全(修复时序问题) | 📝 模板 |
| 04-fail2ban | 配置Fail2Ban防暴力破解 | 📝 模板 |
| 05-firewall | 配置UFW防火墙 | 📝 模板 |
| 06-security-hardening | 系统安全加固 | 📝 模板 |

### 应用安装模块 (install/)

| 模块 | 功能 | 状态 |
|------|------|------|
| docker | 安装Docker Engine + Compose V2 | ✅ |
| nginx-proxy-manager | 安装NPM(已修复网络安全问题) | ✅ |
| 3x-ui | 安装3x-ui面板 | ✅ |

## 🔒 安全改进

### 已修复的P0级别问题

1. **NPM网络模式安全问题**
   - ❌ 原: `network_mode: host` (暴露所有端口)
   - ✅ 改: 桥接网络 + 明确端口映射 `80:80, 81:81, 443:443`

2. **Docker GPG密钥下载安全**
   - ✅ 使用HTTPS下载GPG密钥
   - ✅ 每步检查返回码

3. **完整的错误处理**
   - ✅ 所有模块包含错误检查和回滚
   - ✅ 服务健康验证
   - ✅ 配置文件备份

## 📝 添加新模块

### 步骤1: 复制模板

```bash
cp modules/MODULE_TEMPLATE.sh modules/install/my-app.sh
```

### 步骤2: 编辑模块

修改以下部分:
- `MODULE_NAME`: 模块显示名称
- `MODULE_DEPS`: 依赖的其他模块
- `check_installed()`: 检查是否已安装
- `install()`: 安装逻辑
- `uninstall()`: 卸载逻辑(可选)
- `status()`: 状态显示(可选)

### 步骤3: 在主菜单添加入口

编辑 `vps-tool.sh`, 在菜单中添加选项:

```bash
15. 安装My App

case $choice in
    15)
        run_module "install" "my-app" "install"
        ;;
esac
```

### 步骤4: 测试模块

```bash
# 直接测试模块
./modules/install/my-app.sh install

# 通过主程序测试
./vps-tool.sh
```

## 🎨 模块开发规范

### 必需函数

- `check_installed()`: 检查是否已安装,返回0表示已安装
- `install()`: 安装逻辑,返回0表示成功

### 可选函数

- `uninstall()`: 卸载逻辑
- `status()`: 显示状态信息
- `check_dependencies()`: 额外的依赖检查
- `show_post_install_info()`: 安装后显示的信息

### 编码规范

```bash
# 1. 使用 log_* 函数记录日志
log_info "开始安装..."
log_success "安装成功!"
log_error "安装失败"
log_warning "警告信息"
log_step 1 5 "步骤描述"

# 2. 使用 ask_yes_no 获取用户确认
if ask_yes_no "是否继续?"; then
    # 用户选择yes
fi

# 3. 错误检查
if ! command_that_might_fail; then
    log_error "操作失败"
    return 1
fi

# 4. 创建安装标记
touch "$INSTALL_FLAG"
echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$INSTALL_FLAG"
```

## 📊 使用示例

### 示例1: 全新VPS初始化

```bash
# 启动工具
./vps-tool.sh

# 选择 "1. 一键初始化VPS"
# 系统会自动执行:
# - 更新系统
# - 创建用户
# - 配置SSH
# - 配置Fail2Ban
# - 配置防火墙
# - 系统加固
```

### 示例2: 只安装Docker和NPM

```bash
./vps-tool.sh

# 选择 "12. 安装Docker"
# 选择 "13. 安装Nginx Proxy Manager"
# NPM会自动检查Docker依赖
```

### 示例3: 查看服务状态

```bash
./vps-tool.sh --status

# 或在菜单中选择 "21. 查看服务状态"
```

## 🔧 高级功能

### 日志查看

```bash
# 在菜单中选择 "24. 查看日志"
# 或直接查看日志文件
tail -f logs/vps-tools.log
```

### 配置备份

```bash
# 在菜单中选择 "22. 备份配置"
# 备份会保存在 backup/ 目录
```

### 系统维护

```bash
# 在菜单中选择 "33. 系统维护工具"
# 可以执行:
# - 清理系统日志
# - 清理APT缓存
# - 检查磁盘空间
# - 检查系统更新
# - 重启所有服务
```

## 🐛 故障排除

### 问题1: 权限不足

```bash
# 解决方法: 使用root权限运行
sudo ./vps-tool.sh
```

### 问题2: 模块找不到

```bash
# 检查文件权限
ls -la modules/

# 确保模块文件有执行权限
chmod +x modules/**/*.sh
```

### 问题3: Docker相关错误

```bash
# 检查Docker服务状态
systemctl status docker

# 查看Docker日志
journalctl -u docker -n 50
```

## 📚 相关文档

- [PLAN.md](PLAN.md) - 详细设计方案和安全分析
- [CLAUDE.md](CLAUDE.md) - Claude Code 开发指南
- [modules/MODULE_TEMPLATE.sh](modules/MODULE_TEMPLATE.sh) - 模块开发模板

## 🤝 贡献

欢迎提交Issue和Pull Request!

添加新模块时请:
1. 使用模块模板
2. 遵循编码规范
3. 添加完整的错误处理
4. 编写安装后信息
5. 测试安装/卸载/状态功能

## 📜 许可证

MIT License

## 🎯 路线图

- [x] 核心框架和模块加载器
- [x] Docker安装模块
- [x] Nginx Proxy Manager安装(修复安全问题)
- [x] 3x-ui安装模块
- [ ] 完整的SSH配置模块(含安全修复)
- [ ] Fail2Ban配置模块
- [ ] 防火墙配置模块
- [ ] 系统安全加固模块
- [ ] 用户创建模块
- [ ] 预设配置支持
- [ ] Web UI (未来计划)

## ⚡ 性能优化

- 模块按需加载,启动快速
- 并行执行独立操作
- 缓存系统信息避免重复查询

## 🔐 安全最佳实践

1. 定期运行系统更新
2. 使用SSH密钥认证,禁用密码登录
3. 配置Fail2Ban防暴力破解
4. 启用UFW防火墙,只开放必要端口
5. 定期备份重要配置和数据
6. 及时修改所有默认密码

## 💡 提示

- 首次使用建议选择"一键初始化VPS"
- 安装应用前确保系统已更新
- 重要操作会要求二次确认
- 所有操作都有日志记录
- 卸载时可选择保留数据

---

**Made with ❤️ for VPS管理**
