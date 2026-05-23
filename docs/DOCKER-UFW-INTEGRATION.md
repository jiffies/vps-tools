# Docker + UFW 集成指南

## 问题说明

### 🔴 问题：Docker 绕过 UFW 防火墙

当你使用 Docker 的端口映射（`-p 80:80`）时，Docker 会直接在 iptables 中添加规则，**完全绕过 UFW**。

**表现**：
- UFW 显示端口未开放
- 但外部仍可访问 Docker 容器端口

**原因**：
```
请求流程：
  外部请求 → iptables (Docker规则) → 容器
                       ↑
                  UFW 在这里无效！
```

**验证方式**：
```bash
# 查看 Docker 创建的 NAT 规则
sudo iptables -t nat -L DOCKER -n

# 输出示例：
# DNAT  tcp  --  0.0.0.0/0  0.0.0.0/0  tcp dpt:81  to:172.20.0.2:81
#               ^^^^^^^^^^
#               任何IP都能访问！
```

---

## ✅ 解决方案

### 方案1: 使用 ufw-docker 工具（推荐）

#### 安装步骤

```bash
# 1. 下载工具
sudo wget -O /usr/local/bin/ufw-docker \
  https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker

sudo chmod +x /usr/local/bin/ufw-docker

# 2. 安装 ufw-docker 规则
sudo ufw-docker install

# 3. 重启 UFW
sudo systemctl restart ufw
sudo systemctl restart docker

# 4. 重启 Docker 容器以应用新规则
cd /opt/your-app
sudo docker compose restart
```

#### 使用方法

```bash
# 允许所有人访问容器的某个端口
sudo ufw-docker allow <容器名> <端口>

# 示例：允许访问容器的 8080 端口
sudo ufw-docker allow app-container 8080

# 只允许特定IP访问管理端口
sudo ufw-docker allow app-container 8080 YOUR_IP_ADDRESS

# 查看容器名称
docker ps --format "{{.Names}}"

# 删除规则
sudo ufw-docker delete allow app-container 8080
```

---

### 方案2: 手动配置 /etc/ufw/after.rules（完全控制）

#### 编辑配置文件

```bash
sudo nano /etc/ufw/after.rules
```

#### 在文件末尾添加

```bash
# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]

# 允许来自内网的流量
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

# 将流量转发到 UFW 链进行处理
-A DOCKER-USER -j ufw-user-forward

# 记录并拒绝未授权的流量
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

# 拒绝日志
-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

# 最后返回
-A DOCKER-USER -j RETURN

COMMIT
# END UFW AND DOCKER
```

#### 重启 UFW

```bash
sudo ufw reload
sudo systemctl restart docker
```

---

### 方案3: 限制端口只监听本地（最安全）

修改 Docker Compose 配置，让敏感端口只监听 localhost：

```yaml
# /opt/your-app/docker-compose.yml
services:
  app:
    image: 'your-app:latest'
    restart: unless-stopped
    ports:
      - '0.0.0.0:8080:8080'    # 允许外部访问
      - '127.0.0.1:9000:9000'  # 只允许本地访问（管理端口）
    # ... 其他配置
```

**应用更改**：
```bash
cd /opt/your-app
sudo docker compose down
sudo docker compose up -d
```

**访问方式**：
```bash
# 通过 SSH 隧道访问管理端口
ssh -L 9000:localhost:9000 user@your-server-ip

# 然后在本地浏览器访问
http://localhost:9000
```

---

## 🎯 推荐配置（最佳实践）

### 对于宿主机 Caddy

```bash
# Caddy 不是 Docker 容器,直接由 UFW 管理宿主机端口
sudo ufw allow 80/tcp comment 'Caddy HTTP'
sudo ufw allow 443/tcp comment 'Caddy HTTPS'
```

### 对于其他 Docker 服务

```bash
# 通用模板
sudo ufw-docker allow <容器名> <端口> [来源IP]

# 示例：只允许特定IP访问数据库
sudo ufw-docker allow mysql-1 3306 192.168.1.100
```

---

## 🔍 验证配置

### 查看 UFW 规则

```bash
# 查看 UFW 状态
sudo ufw status verbose

# 查看编号规则
sudo ufw status numbered
```

### 查看 iptables 规则

```bash
# 查看 DOCKER-USER 链（UFW 控制点）
sudo iptables -L DOCKER-USER -n -v

# 应该看到类似：
# Chain DOCKER-USER (1 references)
#  pkts bytes target     prot opt in     out     source               destination
#     0     0 ufw-user-forward  all  --  *      *       0.0.0.0/0            0.0.0.0/0
```

### 测试访问

```bash
# 从外部测试（在你的本地电脑）
# 根据你的规则测试开放端口
curl -I http://YOUR_SERVER_IP:8080
curl -I http://YOUR_SERVER_IP:9000  # 如果限制为本地访问,应该超时或拒绝
```

---

## ⚠️ 故障排查

### 问题1: 配置后仍然可以访问

**解决**：
```bash
# 重启 Docker 和 UFW
sudo systemctl restart ufw
sudo systemctl restart docker

# 重启容器
cd /opt/your-app
sudo docker compose restart
```

### 问题2: 配置后完全无法访问

**解决**：
```bash
# 检查 UFW 规则
sudo ufw status numbered

# 临时禁用 UFW 测试
sudo ufw disable
# 测试访问
# 重新启用
sudo ufw enable
```

### 问题3: ufw-docker 命令不生效

**解决**：
```bash
# 检查 ufw-docker 是否正确安装
which ufw-docker
sudo ufw-docker check

# 重新安装规则
sudo ufw-docker install
sudo ufw reload
```

---

## 📚 参考资料

- [ufw-docker GitHub](https://github.com/chaifeng/ufw-docker)
- [Docker and iptables](https://docs.docker.com/network/iptables/)
- [UFW Documentation](https://help.ubuntu.com/community/UFW)

---

## 🔧 VPS Tools 自动化

未来 vps-tools 将自动处理 Docker + UFW 集成：

```bash
# 安装 Docker 时自动配置
./vps-tool.sh
选择 12: 安装Docker
  ↓
自动检测 UFW
  ↓
配置 Docker + UFW 集成
  ↓
提示需要开放的端口
```

**即将实现**！
