# 故障排查指南

## 问题: 终端显示 `\033[0m` 等颜色代码

### 症状
运行脚本时看到类似这样的输出:
```
\033[0;32m[系统初始化]\033[0m
\033[1m1\033[0m. \033[1;33m(推荐新服务器)\033[0m
```

### 原因
1. **Shell不兼容**: 使用 `sh` 而不是 `bash` 运行脚本
2. **echo命令版本**: 某些系统的 `echo` 不支持 `-e` 参数
3. **终端不支持ANSI颜色**: 非常老的终端

### 解决方案

#### 方案1: 确保使用bash运行(推荐)
```bash
# 不要这样:
sh ./vps-tool.sh

# 应该这样:
bash ./vps-tool.sh

# 或直接执行(需要有执行权限):
./vps-tool.sh
```

#### 方案2: 禁用颜色
```bash
NO_COLOR=1 ./vps-tool.sh
```

#### 方案3: 检查并修复shebang
确保脚本第一行是:
```bash
#!/bin/bash
```

不要是:
```bash
#!/bin/sh
```

#### 方案4: 更新代码
```bash
cd /root/vps-tools
git pull origin main
./vps-tool.sh
```

最新代码已经:
- ✅ 使用 `printf` 替代 `echo -e`
- ✅ 自动检测终端颜色支持
- ✅ 支持 `NO_COLOR` 环境变量

### 诊断命令

运行以下命令诊断问题:

```bash
# 1. 检查当前shell
echo $SHELL
echo $0

# 2. 检查bash版本
bash --version

# 3. 测试颜色支持
printf "\033[32m绿色文字\033[0m\n"

# 4. 检查echo类型
type echo
which echo

# 5. 测试echo -e
echo -e "\033[32m绿色\033[0m"
```

### 预期输出

**正常情况(支持颜色)**:
```
$ printf "\033[32m绿色文字\033[0m\n"
绿色文字  ← 这里应该显示为绿色
```

**异常情况(不支持)**:
```
$ echo -e "\033[32m绿色\033[0m"
\033[32m绿色\033[0m  ← 显示原始代码
```

### 如果诊断发现问题

#### 问题: `echo` 不支持 `-e`
```bash
# 解决: 使用最新版本代码(已改用printf)
git pull origin main
```

#### 问题: 使用了 sh 而不是 bash
```bash
# 解决: 明确使用bash
bash ./vps-tool.sh
```

#### 问题: TERM环境变量未设置
```bash
# 解决: 设置TERM
export TERM=xterm-256color
./vps-tool.sh
```

## 问题: 中文显示乱码

### 症状
中文字符显示为问号或方框

### 解决方案

```bash
# 设置UTF-8编码
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 如果没有中文locale,安装:
apt-get install language-pack-zh-hans

# 然后重新运行
./vps-tool.sh
```

## 问题: 权限被拒绝

### 症状
```
bash: ./vps-tool.sh: Permission denied
```

### 解决方案
```bash
# 添加执行权限
chmod +x vps-tool.sh
chmod +x lib/*.sh
find modules -name "*.sh" -exec chmod +x {} \;

# 然后运行
./vps-tool.sh
```

## 问题: 找不到模块

### 症状
```
[ERROR] 模块不存在: install/docker
```

### 解决方案
```bash
# 1. 检查文件是否存在
ls -la modules/install/docker.sh

# 2. 检查权限
ls -la modules/

# 3. 确保在正确目录
pwd  # 应该是 /root/vps-tools

# 4. 重新克隆
cd /root
rm -rf vps-tools
git clone <repo-url> vps-tools
cd vps-tools
chmod +x vps-tool.sh lib/*.sh
find modules -name "*.sh" -exec chmod +x {} \;
```

## 问题: Docker相关错误

### 症状
```
[ERROR] Docker服务未运行
```

### 解决方案
```bash
# 检查Docker状态
systemctl status docker

# 启动Docker
systemctl start docker

# 设置开机自启
systemctl enable docker

# 如果未安装Docker
./vps-tool.sh
# 选择 12 安装Docker
```

## 问题: 网络连接失败

### 症状
```
[ERROR] 无法连接到互联网
```

### 解决方案
```bash
# 测试网络
ping -c 3 8.8.8.8
ping -c 3 google.com

# 检查DNS
cat /etc/resolv.conf

# 测试HTTP连接
curl -I https://google.com
```

## 获取帮助

如果以上方案都无法解决问题:

1. **查看日志**:
   ```bash
   tail -f logs/vps-tools.log
   ```

2. **启用调试模式**:
   ```bash
   DEBUG=1 ./vps-tool.sh
   ```

3. **提交Issue**:
   - 包含错误信息
   - 包含系统信息 (`uname -a`, `cat /etc/os-release`)
   - 包含相关日志

## 常见命令参考

```bash
# 查看帮助
./vps-tool.sh --help

# 列出所有模块
./vps-tool.sh --list

# 查看服务状态
./vps-tool.sh --status

# 禁用颜色运行
NO_COLOR=1 ./vps-tool.sh

# 调试模式
DEBUG=1 ./vps-tool.sh

# 查看日志
tail -f logs/vps-tools.log
```
