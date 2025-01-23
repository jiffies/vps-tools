#!/bin/bash

# 退出信号处理
trap ctrl_c INT

function ctrl_c() {
    if [[ $first_ctrl_c -eq 0 ]]; then
        first_ctrl_c=1
        echo -e "\n按Ctrl+C第二次以确认退出"
        return
    fi
    echo -e "\n正在退出脚本..."
    exit 1
}

# 初始化变量
first_ctrl_c=0

# 检查是否以root用户运行
if [[ $EUID -ne 0 ]]; then
    echo "此脚本必须以root用户运行！"
    exit 1
fi

# 打印欢迎信息
echo "============================================"
echo "  VPS安全初始化配置脚本"
echo "============================================"
echo "此脚本将帮助您完成以下操作："
echo "1. 更新系统"
echo "2. 创建普通用户并设置sudo权限"
echo "3. 配置SSH安全设置"
echo "4. 安装并配置Fail2Ban"
echo "5. 配置基础防火墙规则"
echo "============================================"

# 1. 更新系统
read -p "是否要更新系统？(y/n): " do_update
if [[ $do_update == "y" ]]; then
    echo ">>> 正在更新系统..."
    apt update && apt upgrade -y
    apt install -y ufw fail2ban sudo vim net-tools
    echo "系统更新完成"
fi

# 2. 创建用户
read -p "是否要创建新用户？(y/n): " do_user
if [[ $do_user == "y" ]]; then
    echo ">>> 创建新用户"
    read -p "请输入新用户名: " username
    while [[ -z "$username" ]] || id "$username" &>/dev/null; do
        echo "用户名无效或已存在，请重新输入。"
        read -p "请输入新用户名: " username
    done

    # 创建用户并设置密码
    adduser $username
    usermod -aG sudo $username
    echo "$username 已添加到sudo组"
fi

# 询问SSH端口
read -p "请输入要使用的SSH端口号(默认22): " ssh_port
ssh_port=${ssh_port:-22}

# 3. 配置SSH
read -p "是否要配置SSH？(y/n): " do_ssh
if [[ $do_ssh == "y" ]]; then
    echo ">>> 配置SSH"
    
    # 如果没有创建新用户，要求输入用户名
    if [[ -z "$username" ]]; then
        read -p "请输入要配置SSH的用户名：" username
        while [[ -z "$username" ]] || ! id "$username" &>/dev/null; do
            echo "用户名无效或不存在，请重新输入。"
            read -p "请输入要配置SSH的用户名：" username
        done
    fi

    # 获取IPv4地址
    SERVER_IPV4=$(curl -s ipinfo.io | grep -oP '(?<="ip": ")[^"]*')
    if [ -z "$SERVER_IPV4" ]; then
        echo "错误：无法获取服务器IPv4地址"
        exit 1
    fi

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    if [ -f "/usr/lib/systemd/system/ssh.socket" ]; then
        cp /usr/lib/systemd/system/ssh.socket /usr/lib/systemd/system/ssh.socket.backup
    fi

    # 检查用户.ssh目录
    ssh_dir="/home/$username/.ssh"
    if [[ ! -d $ssh_dir ]]; then
        mkdir -p $ssh_dir
        chmod 700 $ssh_dir
        chown $username:$username $ssh_dir
    fi

    echo ">>> SSH密钥配置说明 <<<"
    echo "请在您的本地计算机上完成以下步骤："
    echo ""
    echo "Windows用户："
    echo "1. 打开PowerShell"
    echo "2. 创建SSH密钥："
    echo "   - 请在PowerShell中使用ssh-keygen命令"
    echo "   - 建议的文件名：${username}_ed25519"
    echo "   - 密钥将保存在您的用户目录下的.ssh文件夹中"
    echo "   - 可以设置密码短语，也可以留空"
    echo "   具体命令："
    echo "   ssh-keygen -t ed25519 -f \"\$env:USERPROFILE\\.ssh\\${username}_ed25519\" -C \"your_email@example.com\""
    echo ""
    echo "Linux/MacOS用户："
    echo "1. 打开终端"
    echo "2. 创建SSH密钥："
    echo "   - 使用ssh-keygen命令"
    echo "   - 建议的文件名：~/.ssh/${username}_ed25519"
    echo "   - 可以设置密码短语，也可以留空"
    echo "   具体命令："
    echo "   ssh-keygen -t ed25519 -f ~/.ssh/${username}_ed25519 -C \"your_email@example.com\""
    echo ""
    echo "生成密钥后："
    echo "请将公钥（.pub文件）上传到此服务器"
    echo "Windows用户上传命令："
    echo "   scp \"\$env:USERPROFILE\\.ssh\\${username}_ed25519.pub\" $username@$SERVER_IPV4:~/.ssh/authorized_keys"
    echo ""
    echo "Linux/MacOS用户上传命令："
    echo "   ssh-copy-id -i ~/.ssh/${username}_ed25519.pub -p $ssh_port $username@$SERVER_IPV4"
    echo ""
    echo "服务器信息："
    echo "用户名：$username"
    echo "IP地址：$SERVER_IPV4"
    echo "端口：$ssh_port"

    while true; do
        read -p "是否已完成公钥上传？(y/n): " key_uploaded
        if [[ $key_uploaded == "y" ]]; then
            if [[ -f "$ssh_dir/authorized_keys" ]]; then
                echo "已确认公钥上传成功！"
                break
            else
                echo "未检测到authorized_keys文件，请确保正确上传公钥后重试。"
            fi
        else
            echo "请先完成公钥上传后继续。"
        fi
    done

    # 配置SSH
    cat > /etc/ssh/sshd_config <<EOF
Include /etc/ssh/sshd_config.d/*.conf

Port $ssh_port

# 认证配置
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# 其他设置
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# 日志级别
LogLevel INFO
EOF

    # 测试配置文件
    if ! /usr/sbin/sshd -t; then
        echo "SSH配置测试失败，回滚到备份配置..."
        cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
        systemctl restart ssh
        exit 1
    fi

    # 配置 ssh.socket（如果存在）
    if [ -f "/usr/lib/systemd/system/ssh.socket" ]; then
        cat > /usr/lib/systemd/system/ssh.socket <<EOF
[Unit]
Description=OpenBSD Secure Shell server socket
Before=sockets.target ssh.service
ConditionPathExists=!/etc/ssh/sshd_not_to_be_run

[Socket]
ListenStream=$ssh_port
Accept=no
FreeBind=yes

[Install]
WantedBy=sockets.target
RequiredBy=ssh.service
EOF
        # 重载systemd配置
        systemctl daemon-reload
        # 如果socket服务在运行，重启它
        if systemctl is-active ssh.socket >/dev/null 2>&1; then
            systemctl restart ssh.socket
        fi
    fi

    # 重启SSH服务
    systemctl restart ssh
    if ! systemctl is-active ssh >/dev/null 2>&1; then
        echo "SSH服务启动失败，回滚到备份配置..."
        cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
        if [ -f "/usr/lib/systemd/system/ssh.socket.backup" ]; then
            cp /usr/lib/systemd/system/ssh.socket.backup /usr/lib/systemd/system/ssh.socket
        fi
        systemctl daemon-reload
        systemctl restart ssh
        systemctl restart ssh.socket 2>/dev/null
        exit 1
    fi

    # 验证端口监听状态
    sleep 2
    echo "检查SSH端口状态："
    netstat -tuln | grep ":$ssh_port "
    echo "SSH配置完成"
fi

# 4. 配置Fail2Ban
read -p "是否要配置Fail2Ban？(y/n): " do_fail2ban
if [[ $do_fail2ban == "y" ]]; then
    echo ">>> 配置Fail2Ban"
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    systemctl restart fail2ban
    echo "Fail2Ban配置完成"
fi

# 5. 配置防火墙（移到最后）
read -p "是否要配置防火墙？(y/n): " do_firewall
if [[ $do_firewall == "y" ]]; then
    echo ">>> 配置防火墙"
    echo "警告：即将启用防火墙，请确保SSH配置正确且可以连接，否则可能会失去服务器访问权限"
    read -p "是否继续？(y/n): " confirm_firewall
    if [[ $confirm_firewall == "y" ]]; then
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow $ssh_port/tcp comment 'SSH端口'
        ufw --force enable
        echo "防火墙配置完成"
    else
        echo "跳过防火墙配置"
    fi
fi

# 完成提示
echo "============================================"
echo "  VPS安全初始化配置完成！"
echo "============================================"
if [[ $do_user == "y" && $do_ssh == "y" ]]; then
    echo "连接信息："
    echo "主机：$SERVER_IPV4"
    echo "端口：$ssh_port"
    echo "用户名：$username"
    echo "所需文件：之前生成的SSH私钥（${username}_ed25519）"
    echo ""
    echo "Windows连接命令："
    echo "   ssh -p $ssh_port -i \"\$env:USERPROFILE\\.ssh\\${username}_ed25519\" $username@$SERVER_IPV4"
    echo ""
    echo "Linux/MacOS连接命令："
    echo "   ssh -p $ssh_port -i ~/.ssh/${username}_ed25519 $username@$SERVER_IPV4"
fi
echo "============================================"
