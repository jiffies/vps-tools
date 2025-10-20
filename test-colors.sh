#!/bin/bash
# 颜色测试脚本

echo "===== 环境检测 ====="
echo "TERM=$TERM"
echo "NO_COLOR=$NO_COLOR"
echo "标准输出是否是终端: [ -t 1 ] = $( [ -t 1 ] && echo 'yes' || echo 'no' )"
echo ""

echo "===== 测试1: 直接使用转义码 ====="
printf "\033[32m直接printf绿色\033[0m\n"
echo -e "\033[32m直接echo -e绿色\033[0m"
echo ""

echo "===== 测试2: 使用变量(单引号) ====="
GREEN='\033[32m'
NC='\033[0m'
printf "${GREEN}变量printf绿色${NC}\n"
echo -e "${GREEN}变量echo -e绿色${NC}"
echo ""

echo "===== 测试3: 使用变量(使用echo) ====="
echo -e "${GREEN}echo -e变量绿色${NC}"
printf "%b\n" "${GREEN}printf %%b变量绿色${NC}"
printf "%s\n" "${GREEN}printf %%s变量绿色${NC}"
echo ""

echo "===== 测试4: source后的变量 ====="
cat > /tmp/test-color-var.sh << 'EOFX'
GREEN='\033[32m'
NC='\033[0m'
EOFX
source /tmp/test-color-var.sh
printf "${GREEN}source后printf${NC}\n"
echo -e "${GREEN}source后echo -e${NC}"
echo ""

echo "===== 测试5: 检查变量内容 ====="
echo "GREEN变量内容(直接echo): $GREEN"
echo "GREEN变量内容(hexdump):"
echo -n "$GREEN" | od -A x -t x1z -v
