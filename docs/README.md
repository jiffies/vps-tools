# 📚 VPS Tools 文档中心

欢迎使用 VPS Tools 文档中心！这里包含了所有的使用文档、命令参考和故障排查指南。

---

## 🚀 快速开始

### 新用户必读
1. **[项目说明](../README.md)** - 了解VPS Tools是什么
2. **[快速开始](../README.md#快速开始)** - 5分钟上手使用
3. **[常用命令](COMMAND-REFERENCE.md)** - 收藏这个！

### 开发者必读
1. **[模块文档](../MODULES.md)** - 了解所有模块
2. **[开发指南](../CLAUDE.md)** - 如何开发新模块
3. **[项目计划](../PLAN.md)** - 设计决策和安全分析

---

## 📖 文档导航

### 📘 用户文档

| 文档 | 说明 | 适合人群 |
|------|------|----------|
| **[README.md](../README.md)** | 项目说明和快速开始 | 所有用户 ⭐ |
| **[COMMAND-REFERENCE.md](COMMAND-REFERENCE.md)** | 所有组件的常用命令 | 所有用户 ⭐⭐⭐ |
| **[TROUBLESHOOTING.md](../TROUBLESHOOTING.md)** | 故障排查指南 | 遇到问题时 |
| **[DEPLOY.md](../DEPLOY.md)** | 部署说明 | 新服务器部署 |

### 🔧 技术文档

| 文档 | 说明 | 适合人群 |
|------|------|----------|
| **[MODULES.md](../MODULES.md)** | 模块详细说明 | 想深入了解的用户 |
| **[DOCKER-UFW-INTEGRATION.md](DOCKER-UFW-INTEGRATION.md)** | Docker防火墙集成 | 使用Docker的用户 ⭐⭐ |
| **[PLAN.md](../PLAN.md)** | 设计决策和安全分析 | 开发者/高级用户 |
| **[CLAUDE.md](../CLAUDE.md)** | 开发指南和规范 | 开发者 |

---

## 🎯 按需求查找文档

### 我想...

#### 🆕 初次使用VPS
1. 阅读 [README.md](../README.md) 了解项目
2. 按照 [快速开始](../README.md#快速开始) 安装
3. 选择菜单中的 `1. 一键初始化VPS`
4. 参考 [常用命令](COMMAND-REFERENCE.md) 学习Linux

#### 🔒 配置安全的服务器
1. 查看 [MODULES.md](../MODULES.md) 了解安全模块
2. 依次执行:
   - 创建用户 (选项2)
   - 配置SSH (选项3)
   - 配置Fail2Ban (选项4)
   - 配置防火墙 (选项5)
   - 系统加固 (选项6)
3. 参考 [PLAN.md](../PLAN.md#安全分析) 了解安全原理

#### 🐳 使用Docker部署应用
1. 阅读 [DOCKER-UFW-INTEGRATION.md](DOCKER-UFW-INTEGRATION.md)
2. 安装Docker (选项12)
3. 安装应用 (选项13-14)
4. 使用 [ufw-docker 命令](COMMAND-REFERENCE.md#ufw-docker) 开放端口

#### ❌ 遇到问题需要排查
1. 查看 [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
2. 使用 [网络诊断命令](COMMAND-REFERENCE.md#网络诊断)
3. 查看 [日志](COMMAND-REFERENCE.md#日志查看)

#### 💻 开发新模块
1. 阅读 [CLAUDE.md](../CLAUDE.md)
2. 查看 [模块模板](../modules/MODULE_TEMPLATE.sh)
3. 参考 [MODULES.md](../MODULES.md#开发新模块)

---

## 📋 文档目录树

```
vps-tools/
├── README.md                    # 项目主页
├── MODULES.md                   # 模块详细文档
├── PLAN.md                      # 设计决策
├── DEPLOY.md                    # 部署说明
├── SUMMARY.md                   # 项目总结
├── TROUBLESHOOTING.md          # 故障排查
├── CLAUDE.md                    # 开发指南
│
├── docs/                        # 文档目录
│   ├── README.md               # 文档索引(本文件)
│   ├── COMMAND-REFERENCE.md    # 命令参考 ⭐⭐⭐
│   └── DOCKER-UFW-INTEGRATION.md  # Docker防火墙集成
│
├── modules/                     # 模块目录
│   ├── MODULE_TEMPLATE.sh      # 模块模板
│   ├── init/                   # 初始化模块
│   │   ├── 01-system-update.sh
│   │   ├── 02-create-user.sh
│   │   ├── 03-ssh-config.sh
│   │   ├── 04-fail2ban.sh
│   │   ├── 05-firewall.sh
│   │   └── 06-security-hardening.sh
│   └── install/                # 安装模块
│       ├── docker.sh
│       ├── nginx-proxy-manager.sh
│       └── 3x-ui.sh
│
└── lib/                        # 核心库
    ├── common.sh              # 通用函数
    ├── menu.sh                # 菜单系统
    └── module-loader.sh       # 模块加载器
```

---

## 🔍 快速查找命令

### 最常用的命令

| 需求 | 命令 | 文档 |
|------|------|------|
| 启动VPS Tools | `./vps-tool.sh` | [README.md](../README.md) |
| 查看Docker容器 | `docker ps` | [COMMAND-REFERENCE.md](COMMAND-REFERENCE.md#docker) |
| 查看防火墙状态 | `sudo ufw status` | [COMMAND-REFERENCE.md](COMMAND-REFERENCE.md#ufw-防火墙) |
| 开放Docker端口 | `sudo ufw-docker allow <容器> <端口>` | [DOCKER-UFW-INTEGRATION.md](DOCKER-UFW-INTEGRATION.md) |
| 查看NPM日志 | `cd /opt/nginx-proxy-manager && docker compose logs -f` | [COMMAND-REFERENCE.md](COMMAND-REFERENCE.md#nginx-proxy-manager) |
| 查看封禁IP | `sudo fail2ban-client status sshd` | [COMMAND-REFERENCE.md](COMMAND-REFERENCE.md#fail2ban-防火墙) |
| 查看系统资源 | `htop` 或 `top` | [COMMAND-REFERENCE.md](COMMAND-REFERENCE.md#进程管理) |
| 查看磁盘使用 | `df -h` | [COMMAND-REFERENCE.md](COMMAND-REFERENCE.md#磁盘管理) |

---

## 📖 按组件查找

### VPS Tools 主程序
- [基本使用](COMMAND-REFERENCE.md#vps-tools-主程序)
- [模块系统](../MODULES.md)
- [配置文件](../CLAUDE.md)

### 系统初始化
- [系统更新](COMMAND-REFERENCE.md#系统管理)
- [用户管理](COMMAND-REFERENCE.md#用户管理)
- [SSH配置](COMMAND-REFERENCE.md#ssh-管理)
- [Fail2Ban](COMMAND-REFERENCE.md#fail2ban-防火墙)
- [UFW防火墙](COMMAND-REFERENCE.md#ufw-防火墙)
- [安全加固](../MODULES.md#06-security-hardeningsh-)

### 应用安装
- [Docker](COMMAND-REFERENCE.md#docker)
- [Docker Compose](COMMAND-REFERENCE.md#docker-compose)
- [ufw-docker](COMMAND-REFERENCE.md#ufw-docker)
- [Nginx Proxy Manager](COMMAND-REFERENCE.md#nginx-proxy-manager)
- [3x-ui](COMMAND-REFERENCE.md#3x-ui)

### 运维工具
- [日志查看](COMMAND-REFERENCE.md#日志查看)
- [网络诊断](COMMAND-REFERENCE.md#网络诊断)
- [磁盘管理](COMMAND-REFERENCE.md#磁盘管理)
- [进程管理](COMMAND-REFERENCE.md#进程管理)

---

## 💡 使用技巧

### 1. 收藏常用命令
将 [COMMAND-REFERENCE.md](COMMAND-REFERENCE.md) 加入浏览器书签，随时查阅。

### 2. 使用搜索功能
在文档中按 `Ctrl+F` (或 `Cmd+F`) 搜索关键词。

### 3. 参考示例
所有命令都有实际示例，可以直接复制使用。

### 4. 查看日志
遇到问题先查看日志:
```bash
# VPS Tools 日志
tail -f /var/log/vps-tools.log

# Docker 日志
docker logs -f <容器名>

# 系统日志
sudo journalctl -f
```

### 5. 使用帮助命令
大多数命令都支持 `--help`:
```bash
docker --help
docker compose --help
ufw --help
```

---

## 🆘 获取帮助

### 文档中找不到答案？

1. **查看故障排查**: [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
2. **查看日志**: [日志查看命令](COMMAND-REFERENCE.md#日志查看)
3. **检查GitHub Issues**: [提交Issue](https://github.com/anthropics/claude-code/issues)

### 常见问题

| 问题 | 解决方案 |
|------|----------|
| 颜色显示异常 | [TROUBLESHOOTING.md#颜色显示](../TROUBLESHOOTING.md) |
| Docker端口无法访问 | [DOCKER-UFW-INTEGRATION.md](DOCKER-UFW-INTEGRATION.md) |
| SSH无法连接 | [COMMAND-REFERENCE.md#紧急故障处理](COMMAND-REFERENCE.md#紧急故障处理) |
| 磁盘空间不足 | [磁盘管理](COMMAND-REFERENCE.md#磁盘管理) |

---

## 🔄 文档更新日志

### 2025-01-20
- ✅ 创建文档索引 (docs/README.md)
- ✅ 添加完整命令参考 (COMMAND-REFERENCE.md)
- ✅ 添加Docker+UFW集成文档 (DOCKER-UFW-INTEGRATION.md)

### 2025-01-19
- ✅ 完成所有init模块文档 (MODULES.md)
- ✅ 添加故障排查指南 (TROUBLESHOOTING.md)

### 2025-01-18
- ✅ 创建项目文档结构
- ✅ 编写README和PLAN

---

## 📞 联系方式

- **GitHub Issues**: [提交问题或建议](https://github.com/anthropics/claude-code/issues)
- **文档反馈**: 如果文档有错误或需要改进，请提交Issue

---

**提示**: 按 `Ctrl+D` (或 `Cmd+D`) 收藏本页面，方便下次快速访问！
