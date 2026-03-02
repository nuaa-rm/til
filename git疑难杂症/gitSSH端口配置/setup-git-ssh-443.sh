#!/bin/bash

# Git SSH 使用 443 端口配置脚本
# 用于绕过防火墙对标准 SSH 端口 22 的限制

set -e

echo "🔧 配置 Git SSH 使用 443 端口..."

# 确保 .ssh 目录存在
mkdir -p ~/.ssh

# 创建 SSH 配置文件
cat > ~/.ssh/config << 'EOF'
Host github.com
    Hostname ssh.github.com
    Port 443
    User git
EOF

# 设置正确的权限
chmod 600 ~/.ssh/config

echo "✓ SSH 配置文件已创建"

# 添加 GitHub 的主机密钥（443 端口）
ssh-keyscan -p 443 ssh.github.com >> ~/.ssh/known_hosts 2>/dev/null

echo "✓ GitHub 主机密钥已添加"

# 测试连接
echo ""
echo "🧪 测试连接..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo ""
    echo "✅ 配置成功！Git SSH 现在通过 443 端口连接"
    echo ""
    echo "配置内容："
    cat ~/.ssh/config
    echo ""
    echo "现在可以正常使用 git@github.com:xxx/xxx.git 格式的地址进行操作了"
else
    echo ""
    echo "⚠️  连接测试未通过，请检查："
    echo "  1. 是否已生成 SSH 密钥（ssh-keygen -t ed25519 -C \"your_email@example.com\"）"
    echo "  2. 是否已将公钥添加到 GitHub 账户"
    exit 1
fi
