#!/bin/bash

# Docker 安装部分
read -p "是否安装Docker? (y/n): " install_docker
if [ "$install_docker" = "y" ]; then
    echo "步骤1: 更新包索引..."
    sudo apt-get update

    echo "步骤2: 安装必要的依赖包..."
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    echo "步骤3: 添加Docker的官方GPG密钥..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo "步骤4: 设置Docker稳定版仓库..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "步骤5: 再次更新包索引..."
    sudo apt-get update

    echo "步骤6: 安装Docker Engine..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    echo "步骤7: 将当前用户添加到docker组..."
    sudo usermod -aG docker $USER

    echo "步骤8: 启动Docker服务..."
    sudo systemctl start docker
    sudo systemctl enable docker

    echo "步骤9: 验证Docker安装..."
    docker --version

    echo "步骤10: 安装Docker Compose..."
    sudo apt-get install -y docker-compose

    echo "Docker安装完成！请注销并重新登录以应用组权限更改。"
fi

# Nginx Proxy Manager 安装部分
read -p "是否安装Nginx Proxy Manager? (y/n): " install_npm
if [ "$install_npm" = "y" ]; then
    echo "步骤1: 创建Nginx Proxy Manager目录..."
    sudo mkdir -p /opt/npm
    cd /opt/npm

    echo "步骤2: 创建docker-compose.yml文件..."
    sudo bash -c 'cat > docker-compose.yml << EOL
version: "3"
services:
  app:
    image: "jc21/nginx-proxy-manager:latest"
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOL'

    echo "步骤3: 创建数据目录..."
    sudo mkdir -p /opt/npm/data
    sudo mkdir -p /opt/npm/letsencrypt

    echo "步骤4: 设置目录权限..."
    sudo chown -R $USER:$USER /opt/npm

    echo "步骤5: 启动Nginx Proxy Manager..."
    sudo docker-compose up -d

    echo "Nginx Proxy Manager安装完成！"
    SERVER_IPV4=$(curl -s ipinfo.io | grep -oP '(?<="ip": ")[^"]*')
    echo "请访问 http://$SERVER_IPV4:81 进行管理"
    echo "默认管理员邮箱: admin@example.com"
    echo "默认管理员密码: changeme"
fi

echo "所有安装任务已完成！"
