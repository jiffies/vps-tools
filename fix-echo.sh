#!/bin/bash
# 临时脚本: 将所有 echo -e 替换为 printf

find lib modules vps-tool.sh -name "*.sh" -type f -exec sed -i 's/echo -e "\(.*\)"/printf "\1\\n"/g' {} \;

echo "已替换所有 echo -e 为 printf"
