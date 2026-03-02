# ROS 局域网传输禁用

## 问题描述

在某些局域网环境下，ROS（Robot Operating System）的网络通信可能会：
- 占用大量网络带宽
- 与其他 ROS 设备产生冲突（多个 Master 竞争）
- 存在安全风险（未授权访问）
- 触发网络防火墙告警

## 解决方案

通过设置环境变量 `ROS_LOCALHOST_ONLY=1`，使 ROS 只绑定到本地回环地址（127.0.0.1），完全禁用局域网传输。

## 使用方法

```bash
cd /home/baiye/til/ROS疑难杂症/局域网ROS禁用
./disable-ros-lan.sh
```

## 脚本功能

### 1. **自动备份**
在修改前自动备份 `.bashrc` 文件，格式为 `.bashrc.bak.YYYYMMDD_HHMMSS`

### 2. **添加环境变量**
向 `~/.bashrc` 添加以下配置：
```bash
export ROS_LOCALHOST_ONLY=1
```

### 3. **重复检测**
自动检测是否已配置，避免重复添加

## 配置说明

### ROS_LOCALHOST_ONLY

这是 ROS Noetic 及更新版本提供的官方环境变量：

| 值 | 效果 |
|----|------|
| `1` | ROS 只绑定到 localhost (127.0.0.1) |
| `0` 或未设置 | ROS 绑定到所有网络接口 (0.0.0.0) |

### 工作原理

当设置 `ROS_LOCALHOST_ONLY=1` 时：
- ROS Master 只监听 `127.0.0.1:11311`
- 所有 ROS 节点只通过 localhost 通信
- 外部网络无法访问 ROS 系统
- 不会发现或连接局域网中的其他 ROS 设备

### 优点

- ✅ **官方支持**：ROS Noetic+ 官方推荐方法
- ✅ **一行配置**：简单直接，不需要复杂脚本
- ✅ **完全隔离**：彻底禁用局域网通信
- ✅ **无需防火墙**：纯软件配置，不需要 iptables

## 前置条件

- ROS Noetic 或更新版本（支持 `ROS_LOCALHOST_ONLY`）
- 如果使用旧版 ROS，可使用 `export ROS_HOSTNAME=127.0.0.1` 替代

## 验证配置

### 1. 检查环境变量

```bash
source ~/.bashrc
echo $ROS_LOCALHOST_ONLY
# 应输出: 1
```

### 2. 检查监听地址

```bash
# 启动 ROS Master
roscore &
```

在另一个终端：
```bash
# 检查端口监听
netstat -tuln | grep 11311
# 或使用 ss
ss -tuln | grep 11311
```

**正确输出示例**：
```
tcp        0      0 127.0.0.1:11311         0.0.0.0:*               LISTEN
tcp        0      0 ::1:11311               :::*                    LISTEN
```

只应看到 `127.0.0.1`（IPv4）和 `::1`（IPv6），**不应**看到 `0.0.0.0`。

### 3. 测试外部访问

从局域网另一台机器尝试连接：
```bash
# 应该连接失败或超时
rostopic list
```

## 恢复配置

编辑 `~/.bashrc`，删除以下行：
```bash
export ROS_LOCALHOST_ONLY=1
```

然后执行：
```bash
source ~/.bashrc
```

或使用备份文件恢复（如果需要）：
```bash
cp ~/.bashrc.bak.YYYYMMDD_HHMMSS ~/.bashrc
```

## 常见问题

### Q1: 我的 ROS 版本不支持 ROS_LOCALHOST_ONLY 怎么办？

使用以下替代配置（效果相同）：
```bash
export ROS_HOSTNAME=127.0.0.1
export ROS_MASTER_URI=http://127.0.0.1:11311
```

### Q2: 配置后 ROS 节点无法通信？

确保在配置生效后启动新的终端：
```bash
source ~/.bashrc
roscore &
# 在新终端启动节点
rosrun [package] [node]
```

### Q3: 如何临时禁用此配置？

在当前终端执行：
```bash
export ROS_LOCALHOST_ONLY=0
```

这只影响当前终端会话。

## 适用场景

- ✅ 单机开发和测试
- ✅ 隔离敏感 ROS 系统
- ✅ 避免局域网 ROS Master 冲突
- ✅ 安全要求较高的环境
- ❌ 多机器人协作
- ❌ 远程监控和调试
- ❌ 分布式 ROS 集群

## 相关链接

- [ROS 环境变量官方文档](http://wiki.ros.org/ROS/EnvironmentVariables)
- [ROS 网络配置](http://wiki.ros.org/ROS/NetworkSetup)
