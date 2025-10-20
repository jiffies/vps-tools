# 快速部署指南

## 部署到VPS

### 方法1: Git克隆 (推荐)

```bash
# 1. 登录VPS
ssh root@your-vps-ip

# 2. 克隆仓库
cd /root
git clone <你的仓库URL> vps-tools
cd vps-tools

# 3. 设置执行权限
chmod +x vps-tool.sh
chmod +x lib/*.sh
chmod +x modules/**/*.sh

# 4. 运行
./vps-tool.sh
```

### 方法2: 直接上传

```bash
# 在本地执行
cd /home/lcq/scripts
tar -czf vps-tools.tar.gz vps-tools/

# 上传到VPS
scp vps-tools.tar.gz root@your-vps-ip:/root/

# 在VPS上执行
ssh root@your-vps-ip
cd /root
tar -xzf vps-tools.tar.gz
cd vps-tools
chmod +x vps-tool.sh
chmod +x lib/*.sh
chmod +x modules/**/*.sh
./vps-tool.sh
```

### 方法3: 一键部署脚本

创建 `deploy.sh`:

```bash
#!/bin/bash
# deploy.sh - 一键部署脚本

VPS_IP="your-vps-ip"
VPS_USER="root"

echo "开始部署到 $VPS_IP..."

# 1. 打包
tar -czf /tmp/vps-tools.tar.gz \
    --exclude='.git' \
    --exclude='*.log' \
    --exclude='backup/*' \
    -C /home/lcq/scripts vps-tools

# 2. 上传
scp /tmp/vps-tools.tar.gz $VPS_USER@$VPS_IP:/tmp/

# 3. 远程执行
ssh $VPS_USER@$VPS_IP << 'ENDSSH'
cd /root
rm -rf vps-tools
tar -xzf /tmp/vps-tools.tar.gz
cd vps-tools
chmod +x vps-tool.sh
chmod +x lib/*.sh
find modules -name "*.sh" -exec chmod +x {} \;
echo "部署完成! 运行: cd /root/vps-tools && ./vps-tool.sh"
ENDSSH

echo "部署完成!"
```

## 首次使用

```bash
cd /root/vps-tools
./vps-tool.sh

# 或使用一键初始化
./vps-tool.sh --init
```

## 文件权限说明

所有.sh文件需要执行权限(755):
```bash
chmod 755 vps-tool.sh
chmod 755 lib/*.sh
chmod 755 modules/**/*.sh
```

## 验证部署

```bash
# 检查文件结构
tree -L 2

# 检查权限
ls -la vps-tool.sh
ls -la lib/
ls -la modules/

# 测试运行
./vps-tool.sh --help
./vps-tool.sh --list
```

## 故障排除

### 问题1: 权限被拒绝
```bash
chmod +x vps-tool.sh
```

### 问题2: 找不到模块
```bash
find modules -name "*.sh" -exec chmod +x {} \;
```

### 问题3: 颜色显示异常
检查终端是否支持颜色,或设置:
```bash
export TERM=xterm-256color
```

## 目录结构检查清单

部署后应该有以下结构:
```
/root/vps-tools/
├── vps-tool.sh         ✓ 可执行
├── lib/
│   ├── common.sh       ✓ 可执行
│   ├── menu.sh         ✓ 可执行
│   └── module-loader.sh ✓ 可执行
├── modules/
│   ├── install/
│   │   ├── docker.sh   ✓ 可执行
│   │   ├── nginx-proxy-manager.sh ✓ 可执行
│   │   └── 3x-ui.sh    ✓ 可执行
│   ├── init/
│   │   └── 01-system-update.sh ✓ 可执行
│   └── MODULE_TEMPLATE.sh
├── config/
├── logs/
├── backup/
├── README.md
├── PLAN.md
└── CLAUDE.md
```

## 更新部署

```bash
# 在VPS上
cd /root/vps-tools
git pull

# 或重新上传
# (参考方法2)
```
