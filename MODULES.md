# 模块列表

## Init 模块 (系统初始化)

### 01-system-update.sh ✅
- **功能**: 更新系统并安装基础工具
- **包含**: apt update/upgrade, 安装vim, curl, wget等基础工具
- **状态**: 已实现

### 02-create-user.sh ✅
- **功能**: 创建普通用户并配置sudo权限
- **包含**:
  - 创建新用户并设置密码
  - 添加用户到sudo组
  - 验证用户名有效性
- **状态**: 已实现

### 03-ssh-config.sh ✅
- **功能**: SSH安全配置
- **包含**:
  - 配置SSH密钥认证
  - 禁用root登录和密码认证
  - 自定义SSH端口
  - SSH密钥生成指导
  - 自动备份和回滚机制
- **状态**: 已实现

### 04-fail2ban.sh ✅
- **功能**: 配置Fail2Ban防暴力破解
- **包含**:
  - 安装fail2ban
  - 配置SSH保护 (3次失败封禁1小时)
  - 自动检测SSH端口
  - 配置jail.local
- **状态**: 已实现

### 05-firewall.sh ✅
- **功能**: 配置UFW防火墙
- **包含**:
  - 配置UFW基础规则
  - 允许SSH端口
  - 默认拒绝入站，允许出站
  - 自动检测已安装服务端口
  - 安全确认机制防止锁定
- **状态**: 已实现

### 06-security-hardening.sh ✅
- **功能**: 系统安全加固
- **包含**:
  - 禁用不必要的服务
  - 配置内核安全参数 (防SYN flood等)
  - 设置系统资源限制
  - 加固关键文件权限
  - 配置自动安全更新
  - 配置日志审计
- **状态**: 已实现

---

## Install 模块 (应用安装)

### docker.sh ✅
- **功能**: 安装Docker和Docker Compose
- **包含**:
  - 添加Docker官方GPG密钥 (HTTPS)
  - 配置Docker仓库
  - 安装Docker Engine和Docker Compose
  - 配置当前用户docker组权限
- **安全改进**: 使用HTTPS下载GPG密钥
- **状态**: 已实现

### caddy.sh ✅
- **功能**: 安装Caddy并管理通用公网HTTPS应用入口(默认8443,443留给Reality)
- **包含**:
  - 从Caddy官方下载接口安装最新版静态二进制
  - 创建systemd服务
  - 生成主 Caddyfile 并通过 `/etc/caddy/apps.d/*.caddy` 导入应用片段
  - 支持 s-ui dashboard(默认2095),订阅入口默认不公开、可选长随机路径公开到2096
  - 订阅入口自动将外部随机路径 rewrite 到 s-ui 内部 `/sub/`
  - 提供 s-ui + Caddy 配置检验,成功后打印 Dashboard 和订阅入口
  - 支持 Nezha Dashboard(默认8008)和自定义应用反代
  - 引导用户确认域名 A 记录内容指向 VPS 公网 IP 且 Cloudflare 橙云已开启
  - 可选Basic Auth,默认不启用
- **安全改进**:
  - 交互确认是否开放80/tcp和8443/tcp
  - 80仅用于HTTP-01证书验证和HTTP->HTTPS跳转
  - 443/tcp 留给 s-ui/Xray VLESS Reality
  - 禁用TLS-ALPN challenge,避免Cloudflare橙云拦截源站验证
  - 明确区分公网IP和内网IP,提醒Cloudflare A记录内容指向公网IP
- **状态**: 已实现

### s-ui.sh ✅
- **功能**: 安装s-ui管理面板
- **包含**:
  - 下载官方安装脚本
  - 执行交互式安装
  - 清理临时文件
- **状态**: 已实现

### nezha.sh ✅
- **功能**: 安装 Nezha Dashboard/Agent
- **包含**:
  - 下载 Nezha 官方管理脚本
  - 安装前选择服务端 Dashboard 或客户端 Agent
  - 服务端支持 Docker 和独立安装两种官方安装方式
  - 客户端 Agent 通过官方 `agent/install.sh` 安装,需要填入 Dashboard 生成的连接参数
  - 保存 `/opt/nezha/nezha.sh` 作为后续管理入口
  - 安装完成后提示 443/tcp 可用于 Reality,并可通过 Caddy 8443 入口公开面板
- **状态**: 已实现

---

## 模块设计特性

### 统一接口
所有模块支持以下命令:
```bash
./module.sh install    # 安装/配置
./module.sh uninstall  # 卸载
./module.sh status     # 查看状态
```

### 元数据
每个模块包含:
- `MODULE_NAME`: 模块名称
- `MODULE_VERSION`: 版本号
- `MODULE_DEPS`: 依赖的其他模块
- `MODULE_CATEGORY`: 分类 (init/install/manage)
- `MODULE_DESC`: 描述

### 必需函数
- `check_installed()`: 检查是否已安装
- `install()`: 安装/配置逻辑
- `verify_installation()`: 验证安装

### 可选函数
- `uninstall()`: 卸载逻辑
- `status()`: 状态查看
- `check_dependencies()`: 依赖检查

### 安全特性
- ✅ 操作前备份配置文件
- ✅ 失败自动回滚
- ✅ 安装状态标记 (防重复执行)
- ✅ 详细的错误处理
- ✅ 彩色日志输出
- ✅ 操作日志记录

### 用户体验
- 🎨 彩色输出和进度显示
- 📝 详细的安装后信息
- ⚠️ 危险操作二次确认
- 🔄 支持重新配置
- 📊 清晰的状态查看

---

## 依赖关系

```
系统初始化流程:
01-system-update (无依赖)
  ↓
02-create-user (无依赖)
  ↓
03-ssh-config (建议先创建用户)
  ↓
04-fail2ban (需要SSH端口信息)
  ↓
05-firewall (需要SSH端口信息)
  ↓
06-security-hardening (无依赖)

应用安装流程:
docker (无依赖,按需安装)
  ↓
s-ui (无依赖)
  ↓
nezha (无依赖,按需选择服务端或客户端)
  ↓
caddy (无依赖,建议在应用安装完成后配置网关)
```

---

## 使用示例

### 单独执行模块
```bash
# 创建用户
./modules/init/02-create-user.sh install

# 配置SSH
./modules/init/03-ssh-config.sh install

# 查看状态
./modules/init/03-ssh-config.sh status
```

### 使用主程序
```bash
# 交互式菜单
./vps-tool.sh

# 一键初始化
选择 1: 一键初始化VPS

# 单独执行某个步骤
选择 2-7: 执行特定的初始化步骤
```

---

## 开发新模块

参考 `modules/MODULE_TEMPLATE.sh` 模板创建新模块。

### 步骤:
1. 复制模板到对应目录 (init/install/manage)
2. 修改模块元数据
3. 实现必需函数
4. 添加到主菜单 (vps-tool.sh)
5. 测试独立运行和集成运行

---

## 迁移说明

### 从 initVPS.sh 迁移
- ✅ 01-system-update: 系统更新部分
- ✅ 02-create-user: 创建用户部分
- ✅ 03-ssh-config: SSH配置部分
- ✅ 04-fail2ban: Fail2Ban配置部分
- ✅ 05-firewall: UFW配置部分
- ✅ 06-security-hardening: 新增安全加固

### 从 installApp.sh 迁移
- ✅ docker: Docker安装部分
- ✅ caddy: Caddy通用 HTTPS 入口管理
- ✅ s-ui: s-ui安装部分
- ✅ nezha: Nezha Dashboard/Agent安装部分

### 改进点
- 模块化设计，可单独使用
- 添加状态检查和卸载功能
- 增强错误处理和回滚机制
- 自动检测依赖和配置
- 统一的日志和输出格式
- 安全性增强 (bridge网络, HTTPS等)
