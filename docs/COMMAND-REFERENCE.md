# VPS Tools 常用命令参考

## 📚 目录

- [VPS Tools 主程序](#vps-tools-主程序)
- [系统管理](#系统管理)
- [用户管理](#用户管理)
- [SSH 管理](#ssh-管理)
- [Fail2Ban 防火墙](#fail2ban-防火墙)
- [UFW 防火墙](#ufw-防火墙)
- [Docker](#docker)
- [Docker Compose](#docker-compose)
- [ufw-docker](#ufw-docker)
- [Nginx Proxy Manager](#nginx-proxy-manager)
- [s-ui](#s-ui)
- [日志查看](#日志查看)
- [网络诊断](#网络诊断)
- [磁盘管理](#磁盘管理)
- [进程管理](#进程管理)

---

## VPS Tools 主程序

### 基本使用
```bash
# 启动交互式菜单
./vps-tool.sh

# 查看帮助
./vps-tool.sh --help

# 列出所有模块
./vps-tool.sh --list

# 查看状态
./vps-tool.sh --status
```

### 独立运行模块
```bash
# 语法
./modules/<category>/<module>.sh {install|uninstall|status}

# 示例
./modules/init/01-system-update.sh install
./modules/install/docker.sh status
./modules/install/nginx-proxy-manager.sh uninstall
```

### 配置文件
```bash
# VPS Tools 日志
tail -f /var/log/vps-tools.log

# 模块状态标记
ls -la /var/log/vps-tools/

# 配置目录
~/.claude/CLAUDE.md          # 用户全局配置
./PLAN.md                    # 项目计划文档
```

---

## 系统管理

### 系统更新
```bash
# 更新软件包列表
sudo apt update

# 升级所有软件包
sudo apt upgrade -y

# 完整升级(包括移除过时包)
sudo apt full-upgrade -y

# 清理不需要的包
sudo apt autoremove -y
sudo apt autoclean

# 查看可升级的包
apt list --upgradable
```

### 系统信息
```bash
# 系统版本
lsb_release -a
cat /etc/os-release

# 内核版本
uname -a
uname -r

# CPU信息
lscpu
cat /proc/cpuinfo

# 内存信息
free -h
cat /proc/meminfo

# 磁盘使用
df -h
du -sh /*

# 系统负载
uptime
top
htop
```

### 自动更新
```bash
# 查看自动更新配置
cat /etc/apt/apt.conf.d/50unattended-upgrades

# 查看自动更新日志
cat /var/log/unattended-upgrades/unattended-upgrades.log

# 手动触发自动更新
sudo unattended-upgrade -d

# 重新配置
sudo dpkg-reconfigure -plow unattended-upgrades
```

---

## 用户管理

### 用户操作
```bash
# 创建用户
sudo adduser username

# 添加用户到sudo组
sudo usermod -aG sudo username

# 删除用户
sudo deluser username
sudo deluser --remove-home username

# 切换用户
su - username

# 查看当前用户
whoami
id

# 查看所有用户
cat /etc/passwd
cut -d: -f1 /etc/passwd

# 查看用户组
groups username
id username

# 修改用户密码
sudo passwd username
passwd  # 修改当前用户密码
```

### sudo 配置
```bash
# 编辑sudo配置
sudo visudo

# 查看sudo权限
sudo -l

# 以root身份执行
sudo -i
sudo su -

# 查看sudo日志
sudo cat /var/log/auth.log | grep sudo
```

---

## SSH 管理

### SSH 连接
```bash
# 基本连接
ssh user@host

# 指定端口
ssh -p 22 user@host

# 使用密钥
ssh -i ~/.ssh/id_ed25519 user@host

# 指定端口和密钥
ssh -p 2222 -i ~/.ssh/key user@host

# SSH 隧道(端口转发)
ssh -L 本地端口:目标主机:目标端口 user@host
ssh -L 8081:localhost:81 user@vps-ip

# 后台运行隧道
ssh -fNL 8081:localhost:81 user@vps-ip
```

### SSH 密钥管理
```bash
# 生成SSH密钥(推荐 ed25519)
ssh-keygen -t ed25519 -f ~/.ssh/mykey -C "your_email@example.com"

# 生成RSA密钥
ssh-keygen -t rsa -b 4096 -f ~/.ssh/mykey

# 上传公钥到服务器
ssh-copy-id -i ~/.ssh/mykey.pub user@host

# 手动添加公钥
cat ~/.ssh/mykey.pub | ssh user@host "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# 设置正确权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# 查看公钥指纹
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

### SSH 服务管理
```bash
# 重启SSH服务
sudo systemctl restart ssh
sudo systemctl restart sshd  # CentOS/RHEL

# 查看SSH状态
sudo systemctl status ssh

# 测试配置文件
sudo sshd -t

# 查看SSH日志
sudo tail -f /var/log/auth.log
sudo journalctl -u ssh -f

# 编辑SSH配置
sudo nano /etc/ssh/sshd_config

# 查看当前SSH连接
who
w
last
```

### SSH 配置文件
```bash
# 客户端配置 (~/.ssh/config)
Host myserver
    HostName 47.79.123.198
    Port 22
    User myuser
    IdentityFile ~/.ssh/mykey
    ServerAliveInterval 60

# 使用别名连接
ssh myserver

# 服务器配置 (/etc/ssh/sshd_config)
Port 22
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
```

---

## Fail2Ban 防火墙

### 基本命令
```bash
# 查看状态
sudo fail2ban-client status

# 查看特定jail状态
sudo fail2ban-client status sshd
sudo fail2ban-client status sshd-ddos

# 查看所有jail
sudo fail2ban-client status | grep "Jail list"
```

### 封禁管理
```bash
# 查看封禁的IP
sudo fail2ban-client status sshd | grep "Banned IP"

# 手动封禁IP
sudo fail2ban-client set sshd banip 192.168.1.100

# 解封IP
sudo fail2ban-client set sshd unbanip 192.168.1.100

# 解封所有IP
sudo fail2ban-client unban --all

# 查看封禁历史
sudo zgrep 'Ban' /var/log/fail2ban.log*
```

### 服务管理
```bash
# 启动/停止/重启
sudo systemctl start fail2ban
sudo systemctl stop fail2ban
sudo systemctl restart fail2ban

# 重载配置
sudo fail2ban-client reload

# 查看日志
sudo tail -f /var/log/fail2ban.log

# 查看实时封禁
sudo tail -f /var/log/fail2ban.log | grep Ban
```

### 配置文件
```bash
# 主配置
sudo nano /etc/fail2ban/jail.local

# 默认配置(不要直接修改)
/etc/fail2ban/jail.conf

# 过滤器
/etc/fail2ban/filter.d/

# 动作
/etc/fail2ban/action.d/
```

---

## UFW 防火墙

### 基本操作
```bash
# 启用防火墙
sudo ufw enable

# 禁用防火墙
sudo ufw disable

# 查看状态
sudo ufw status
sudo ufw status verbose
sudo ufw status numbered

# 重载规则
sudo ufw reload

# 重置防火墙(删除所有规则)
sudo ufw --force reset
```

### 规则管理
```bash
# 允许端口
sudo ufw allow 22/tcp
sudo ufw allow 80
sudo ufw allow 443/tcp comment 'HTTPS'

# 拒绝端口
sudo ufw deny 23

# 允许特定IP
sudo ufw allow from 192.168.1.100

# 允许特定IP访问特定端口
sudo ufw allow from 192.168.1.100 to any port 22

# 允许IP段
sudo ufw allow from 192.168.1.0/24

# 删除规则(按编号)
sudo ufw status numbered
sudo ufw delete 3

# 删除规则(按内容)
sudo ufw delete allow 80/tcp
```

### 默认策略
```bash
# 默认拒绝入站
sudo ufw default deny incoming

# 默认允许出站
sudo ufw default allow outgoing

# 查看默认策略
sudo ufw status verbose
```

### 应用配置
```bash
# 查看可用应用
sudo ufw app list

# 查看应用信息
sudo ufw app info 'Nginx Full'

# 允许应用
sudo ufw allow 'Nginx Full'
```

### 日志
```bash
# 启用日志
sudo ufw logging on
sudo ufw logging medium

# 查看日志
sudo tail -f /var/log/ufw.log

# 禁用日志
sudo ufw logging off
```

---

## Docker

### Docker 服务
```bash
# 启动/停止/重启Docker
sudo systemctl start docker
sudo systemctl stop docker
sudo systemctl restart docker

# 查看Docker状态
sudo systemctl status docker
docker info

# 查看版本
docker --version
docker version
```

### 容器管理
```bash
# 查看运行中的容器
docker ps

# 查看所有容器(包括停止的)
docker ps -a

# 查看容器详细信息
docker inspect <容器ID或名称>

# 启动/停止/重启容器
docker start <容器名>
docker stop <容器名>
docker restart <容器名>

# 删除容器
docker rm <容器名>
docker rm -f <容器名>  # 强制删除运行中的容器

# 删除所有停止的容器
docker container prune

# 进入容器
docker exec -it <容器名> /bin/bash
docker exec -it <容器名> sh

# 查看容器日志
docker logs <容器名>
docker logs -f <容器名>  # 实时查看
docker logs --tail 100 <容器名>  # 查看最后100行

# 查看容器资源使用
docker stats
docker stats <容器名>

# 查看容器端口映射
docker port <容器名>
```

### 镜像管理
```bash
# 查看镜像列表
docker images
docker image ls

# 拉取镜像
docker pull nginx:latest
docker pull ubuntu:22.04

# 删除镜像
docker rmi <镜像ID>
docker rmi nginx:latest

# 删除未使用的镜像
docker image prune
docker image prune -a

# 搜索镜像
docker search nginx

# 查看镜像详细信息
docker inspect <镜像ID>

# 查看镜像构建历史
docker history <镜像名>
```

### 网络管理
```bash
# 查看网络
docker network ls

# 创建网络
docker network create mynetwork
docker network create --driver bridge mynetwork

# 删除网络
docker network rm mynetwork

# 查看网络详情
docker network inspect bridge

# 连接容器到网络
docker network connect mynetwork <容器名>

# 断开容器网络
docker network disconnect mynetwork <容器名>
```

### 卷管理
```bash
# 查看卷
docker volume ls

# 创建卷
docker volume create myvolume

# 删除卷
docker volume rm myvolume

# 删除未使用的卷
docker volume prune

# 查看卷详情
docker volume inspect myvolume
```

### 系统清理
```bash
# 清理所有未使用的资源
docker system prune

# 清理所有(包括未使用的镜像)
docker system prune -a

# 查看磁盘使用
docker system df

# 清理构建缓存
docker builder prune
```

---

## Docker Compose

### 基本命令
```bash
# 启动服务(后台运行)
docker compose up -d

# 启动服务(前台运行,查看日志)
docker compose up

# 停止服务
docker compose down

# 停止并删除卷
docker compose down -v

# 重启服务
docker compose restart

# 重启特定服务
docker compose restart app
```

### 服务管理
```bash
# 查看服务状态
docker compose ps

# 查看服务日志
docker compose logs
docker compose logs -f  # 实时查看
docker compose logs app  # 查看特定服务
docker compose logs --tail=100 app

# 执行命令
docker compose exec app bash
docker compose exec app sh

# 拉取镜像
docker compose pull

# 构建镜像
docker compose build

# 启动特定服务
docker compose up -d app

# 停止特定服务
docker compose stop app

# 删除服务容器
docker compose rm app
```

### 配置管理
```bash
# 验证配置文件
docker compose config

# 查看配置
docker compose config --services
docker compose config --volumes

# 使用特定配置文件
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### 扩展和更新
```bash
# 扩展服务实例
docker compose up -d --scale app=3

# 更新服务(拉取新镜像并重启)
docker compose pull
docker compose up -d

# 重建并启动
docker compose up -d --build
docker compose up -d --force-recreate
```

---

## ufw-docker

### 基本命令
```bash
# 安装 ufw-docker
sudo wget -O /usr/local/bin/ufw-docker \
  https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
sudo chmod +x /usr/local/bin/ufw-docker
sudo ufw-docker install

# 查看帮助
ufw-docker help
```

### 端口管理
```bash
# 允许所有人访问容器端口
sudo ufw-docker allow <容器名> <端口>

# 示例
sudo ufw-docker allow nginx-proxy-manager-app-1 80
sudo ufw-docker allow nginx-proxy-manager-app-1 443

# 只允许特定IP访问
sudo ufw-docker allow <容器名> <端口> <IP地址>

# 示例
sudo ufw-docker allow nginx-proxy-manager-app-1 81 192.168.1.100
```

### 规则管理
```bash
# 查看规则
sudo ufw-docker list

# 删除规则
sudo ufw-docker delete allow <容器名> <端口>
sudo ufw-docker delete allow nginx-proxy-manager-app-1 81

# 查看服务状态
sudo ufw-docker status

# 检查配置
sudo ufw-docker check
```

### 实用技巧
```bash
# 查看容器名称
docker ps --format "{{.Names}}"

# 查看容器ID和名称
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Ports}}"

# 组合使用
CONTAINER=$(docker ps --filter ancestor=jc21/nginx-proxy-manager:latest --format "{{.Names}}")
sudo ufw-docker allow $CONTAINER 80
```

---

## Nginx Proxy Manager

### 访问管理
```bash
# 默认访问地址
http://YOUR_IP:81

# 默认凭据
邮箱: admin@example.com
密码: changeme
```

### Docker Compose 管理
```bash
# 进入NPM目录
cd /opt/nginx-proxy-manager

# 启动
docker compose up -d

# 停止
docker compose down

# 重启
docker compose restart

# 查看日志
docker compose logs -f

# 更新到最新版本
docker compose pull
docker compose up -d

# 查看状态
docker compose ps
```

### 容器管理
```bash
# 查看NPM容器
docker ps | grep nginx-proxy-manager

# 进入容器
docker exec -it nginx-proxy-manager-app-1 sh

# 查看容器日志
docker logs -f nginx-proxy-manager-app-1

# 重启容器
docker restart nginx-proxy-manager-app-1
```

### 数据管理
```bash
# 数据目录
cd /opt/nginx-proxy-manager

# 查看数据大小
du -sh data/
du -sh letsencrypt/

# 备份数据
tar -czf npm-backup-$(date +%Y%m%d).tar.gz \
  -C /opt nginx-proxy-manager

# 恢复数据
tar -xzf npm-backup-20250120.tar.gz -C /opt

# 查看数据库
sqlite3 /opt/nginx-proxy-manager/data/database.sqlite
.tables
.quit
```

### SSL 证书管理
```bash
# SSL 证书目录
ls -la /opt/nginx-proxy-manager/letsencrypt/

# 查看证书
sudo certbot certificates

# 强制更新证书(在容器内)
docker exec nginx-proxy-manager-app-1 certbot renew --force-renewal
```

---

## s-ui

### 基本命令
```bash
# 启动s-ui管理面板
sudo s-ui

# 常用选项
1  - 安装
2  - 更新
3  - 卸载
4  - 重置用户名密码
5  - 重置面板设置
6  - 设置面板端口
7  - 查看当前面板设置
```

### 服务管理
```bash
# 启动
sudo systemctl start s-ui

# 停止
sudo systemctl stop s-ui

# 重启
sudo systemctl restart s-ui

# 查看状态
sudo systemctl status s-ui

# 开机自启
sudo systemctl enable s-ui

# 禁用自启
sudo systemctl disable s-ui
```

### 日志查看
```bash
# 查看日志
sudo s-ui log

# 实时查看
sudo journalctl -u s-ui -f

# 查看最近日志
sudo journalctl -u s-ui -n 100
```

### 配置管理
```bash
# 配置文件目录
/usr/local/s-ui/

# 数据库
/etc/s-ui/s-ui.db

# 备份
sudo cp /etc/s-ui/s-ui.db /root/s-ui-backup-$(date +%Y%m%d).db
```

---

## 日志查看

### 系统日志
```bash
# 查看系统日志
sudo journalctl

# 实时查看
sudo journalctl -f

# 查看特定服务
sudo journalctl -u ssh
sudo journalctl -u docker
sudo journalctl -u nginx

# 查看最近N行
sudo journalctl -n 100

# 查看时间范围
sudo journalctl --since "2025-01-20 10:00:00"
sudo journalctl --since "1 hour ago"
sudo journalctl --since today

# 按优先级过滤
sudo journalctl -p err  # 只看错误
sudo journalctl -p warning  # 警告及以上
```

### 应用日志
```bash
# 认证日志(SSH登录等)
sudo tail -f /var/log/auth.log

# 系统日志
sudo tail -f /var/log/syslog

# 内核日志
sudo dmesg
sudo dmesg -T  # 带时间戳

# VPS Tools 日志
tail -f /var/log/vps-tools.log

# Docker 日志
sudo journalctl -u docker -f
```

### 日志管理
```bash
# 清理旧日志
sudo journalctl --vacuum-time=7d  # 保留7天
sudo journalctl --vacuum-size=500M  # 限制大小

# 查看日志大小
sudo journalctl --disk-usage

# 日志轮转配置
/etc/logrotate.conf
/etc/logrotate.d/
```

---

## 网络诊断

### 连接测试
```bash
# Ping测试
ping -c 4 google.com
ping 8.8.8.8

# 端口测试
telnet IP PORT
nc -zv IP PORT

# HTTP测试
curl -I http://example.com
wget --spider http://example.com
```

### 端口和连接
```bash
# 查看监听端口
sudo netstat -tuln
sudo ss -tuln

# 查看所有连接
sudo netstat -tan
sudo ss -tan

# 查看特定端口
sudo netstat -tuln | grep :80
sudo lsof -i :80

# 查看进程占用端口
sudo lsof -i -P -n | grep LISTEN
```

### IP和路由
```bash
# 查看IP地址
ip addr
ip a
ifconfig

# 查看路由表
ip route
route -n

# 查看公网IP
curl ifconfig.me
curl ipinfo.io
curl ip.sb

# DNS查询
nslookup google.com
dig google.com
host google.com
```

### 防火墙检查
```bash
# UFW状态
sudo ufw status verbose

# iptables规则
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v

# 查看Docker规则
sudo iptables -L DOCKER -n -v
sudo iptables -t nat -L DOCKER -n -v
```

---

## 磁盘管理

### 磁盘使用
```bash
# 查看磁盘使用
df -h

# 查看目录大小
du -sh /var/log
du -sh /opt/*

# 查看最大文件
du -ah /var/log | sort -rh | head -20

# 查看inode使用
df -i
```

### 查找大文件
```bash
# 查找大于100M的文件
find / -type f -size +100M

# 查找大于1G的文件并显示大小
find / -type f -size +1G -exec ls -lh {} \;

# 查找并排序
find /var -type f -size +10M -exec du -h {} \; | sort -rh | head -20
```

### 清理空间
```bash
# 清理APT缓存
sudo apt clean
sudo apt autoclean
sudo apt autoremove

# 清理日志
sudo journalctl --vacuum-time=3d
sudo rm -rf /var/log/*.gz

# 清理Docker
docker system prune -a
docker volume prune

# 清理临时文件
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
```

---

## 进程管理

### 查看进程
```bash
# 查看所有进程
ps aux
ps -ef

# 实时查看
top
htop

# 查看特定进程
ps aux | grep nginx
pgrep -a nginx

# 查看进程树
pstree
ps auxf
```

### 进程控制
```bash
# 杀死进程
kill PID
kill -9 PID  # 强制杀死

# 按名称杀死
pkill nginx
killall nginx

# 查看进程详情
cat /proc/PID/status
cat /proc/PID/cmdline
```

### 资源监控
```bash
# CPU使用
top -o %CPU
ps aux --sort=-%cpu | head

# 内存使用
free -h
ps aux --sort=-%mem | head

# 磁盘IO
iotop
iostat

# 网络IO
iftop
nethogs
```

---

## 🔖 快速参考

### 常用组合命令

```bash
# 查看所有Docker容器和端口
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 清理Docker并释放空间
docker system prune -a && docker volume prune

# 查看系统资源使用
echo "=== CPU ===" && uptime && \
echo "=== 内存 ===" && free -h && \
echo "=== 磁盘 ===" && df -h

# 查看所有监听端口
sudo netstat -tuln | grep LISTEN

# 查看防火墙和Docker规则
echo "=== UFW ===" && sudo ufw status numbered && \
echo "=== Docker ===" && sudo ufw-docker list

# 备份重要数据
tar -czf backup-$(date +%Y%m%d).tar.gz \
  /opt/nginx-proxy-manager \
  /etc/s-ui
```

### 紧急故障处理

```bash
# SSH无法连接
# 1. 通过VPS控制台登录
# 2. 检查SSH服务
sudo systemctl status ssh
sudo systemctl restart ssh

# 3. 检查防火墙
sudo ufw status
sudo ufw allow 22/tcp

# 磁盘满了
# 1. 查找大文件
du -sh /* | sort -rh | head -10

# 2. 清理Docker
docker system prune -a

# 3. 清理日志
sudo journalctl --vacuum-size=100M

# 服务无法访问
# 1. 检查容器状态
docker ps

# 2. 检查防火墙
sudo ufw-docker list

# 3. 检查日志
docker logs <容器名>
```

---

## 📚 相关文档

- [README.md](../README.md) - 项目说明
- [MODULES.md](../MODULES.md) - 模块文档
- [DOCKER-UFW-INTEGRATION.md](DOCKER-UFW-INTEGRATION.md) - Docker防火墙集成
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - 故障排查

---

**提示**: 将此文档收藏或打印出来,方便随时查阅！
