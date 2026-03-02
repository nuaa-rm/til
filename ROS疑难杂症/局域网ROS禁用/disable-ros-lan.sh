#!/bin/bash

# ROS 局域网传输禁用脚本
# 通过设置 ROS_LOCALHOST_ONLY=1 限制 ROS 只在本地通信

set -e

echo "🔧 配置禁用 ROS 局域网传输..."

# 获取当前用户
CURRENT_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)

# 备份现有 .bashrc
if [ -f "$USER_HOME/.bashrc" ]; then
    cp "$USER_HOME/.bashrc" "$USER_HOME/.bashrc.bak.$(date +%Y%m%d_%H%M%S)"
    echo "📦 已备份 .bashrc 到 .bashrc.bak.$(date +%Y%m%d_%H%M%S)"
fi

# 检查是否已配置
if grep -q "export ROS_LOCALHOST_ONLY=1" "$USER_HOME/.bashrc" 2>/dev/null; then
    echo "⚠️  检测到已配置 ROS_LOCALHOST_ONLY=1"
    echo "是否重新配置？(y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "取消操作"
        exit 0
    fi
    # 删除现有配置行
    sed -i '/export ROS_LOCALHOST_ONLY=1/d' "$USER_HOME/.bashrc"
fi

# 添加 ROS_LOCALHOST_ONLY 配置到 .bashrc
cat >> "$USER_HOME/.bashrc" << 'EOF'

# ROS 局域网传输禁用配置
export ROS_LOCALHOST_ONLY=1
EOF

echo "✅ ROS 局域网传输禁用配置完成！"
echo ""
echo "📋 配置内容："
echo "  export ROS_LOCALHOST_ONLY=1"
echo ""
echo "📌 说明："
echo "  - ROS_LOCALHOST_ONLY=1 使 ROS 只绑定到 localhost (127.0.0.1)"
echo "  - 禁止外部网络访问 ROS 节点和服务"
echo "  - 适用于单机开发和测试环境"
echo ""
echo "🔄 使配置生效："
echo "  方法1: source ~/.bashrc"
echo "  方法2: 重启终端"
echo ""
echo "🧪 验证配置："
echo "  执行 'echo \$ROS_LOCALHOST_ONLY' 应显示 '1'"
echo "  运行 roscore 后，用 'netstat -tuln | grep 11311' 检查只监听 127.0.0.1"
echo ""
echo "⚠️  恢复配置："
echo "  编辑 ~/.bashrc，删除 'export ROS_LOCALHOST_ONLY=1' 行"
