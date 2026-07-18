# 第五章：部署

## 概述

代码调试完成后，需要将节点稳定运行在目标机器上。本章介绍两个主题：CLion 远程部署与调试（直接在开发机上编译、同步、远程运行），以及 systemd 服务配置（让 ROS2 节点开机自启、崩溃自恢复）。

练习文件：`ch5_deploy/simple_node.cpp` + `my_node.service.template`

---

## 5.1 CLion 远程部署

### 概念

CLion 的远程开发模式：在本地编写代码，编译器和运行环境在远程机器（机器人、服务器）上。文件通过 SFTP 自动同步，调试通过 GDB Remote 协议进行，体验接近本地开发。

### 配置步骤

#### Step 1：配置 SFTP 连接

菜单 **Settings → Build, Execution, Deployment → Deployment → +（添加）→ SFTP**

| 字段 | 值 |
|------|-----|
| Host | 远程机器 IP，如 `192.168.1.100` |
| Port | `22` |
| Authentication | Password 或 Key pair |
| Root path | 远程机器上的项目根目录，如 `/home/robot/ros_ws` |

切换到 **Mappings** 标签页：

| 字段 | 值 |
|------|-----|
| Local path | 本地项目目录 |
| Deployment path | 远程相对于 Root path 的路径 |

#### Step 2：配置远程工具链

**Settings → Build, Execution, Deployment → Toolchains → +（添加）→ Remote Host**

- **Credentials**：选择 Step 1 配置的 SFTP 连接
- CLion 会自动检测远程的 CMake、编译器路径
- 如需手动指定：填写 `/usr/bin/cmake`、`/usr/bin/g++` 等

#### Step 3：配置 CMake Profile

**Settings → Build, Execution, Deployment → CMake → +（添加）**

- **Toolchain**：选择 Step 2 配置的远程工具链
- **Build directory**：`cmake-build-remote-debug`（与本地区分）

#### Step 4：自动同步

**Settings → Build, Execution, Deployment → Deployment → Options**

- 勾选 **Upload changed files automatically to the default server**
- 选择触发时机：保存时 / 编辑时

保存文件后 CLion 自动将改动同步到远程机器。

#### Step 5：编译和运行

工具栏选择远程 CMake Profile → 点击编译/运行按钮，CLion 在远程机器上编译并运行，输出显示在本地 Run 面板。

---

### 远程调试（gdbserver）

适用于无法直接使用 CLion 远程工具链的场景（嵌入式板、权限受限的机器）。

**目标机器启动 gdbserver：**

```bash
# 调试指定可执行文件
gdbserver :1234 ./simple_node

# 附加到已运行的进程
gdbserver :1234 --attach <PID>
```

**CLion 配置 GDB Remote：**

1. **Run → Edit Configurations → + → GDB Remote Debug**
2. 填写：
   - **Target remote args**：`192.168.1.100:1234`
   - **Symbol file**（本地带 debug 符号的可执行文件路径）
   - **Path mappings**：远程路径 → 本地路径（CLion 用此跳转源码）
3. 点击 Debug 按钮，CLion 连接远程 gdbserver，体验与本地调试完全一致

**ROS2 节点远程调试：**

```bash
# 目标机器
source /opt/ros/humble/setup.bash
source /opt/ros_ws/install/setup.bash
gdbserver :1234 /opt/ros_ws/install/debug_ch5/lib/debug_ch5/simple_node
```

---

## 5.2 systemd 服务配置

### 为什么用 systemd

| 需求 | systemd 提供的能力 |
|------|------------------|
| 开机自启 | `WantedBy=multi-user.target` + `systemctl enable` |
| 崩溃自恢复 | `Restart=on-failure` + `RestartSec=5s` |
| 依赖顺序 | `After=network.target` 等 |
| 日志管理 | `StandardOutput=journal`，`journalctl` 查看 |
| 资源限制 | `CPUQuota`、`MemoryMax` |

### service 文件详解

```ini
[Unit]
Description=ROS2 simple_node heartbeat publisher
# 在 network.target 之后启动
# 如果依赖其他 ROS2 节点，在这里添加：After=other_node.service
After=network.target

[Service]
Type=simple          # 进程启动后即视为就绪（适合 ROS2 节点）
User=robot           # 以 robot 用户身份运行，避免 root 权限过大
WorkingDirectory=/opt/ros_ws

# 环境变量（不能用来 source bash 脚本，只能设置 KEY=VALUE）
Environment="ROS_DOMAIN_ID=0"
Environment="RCUTILS_LOGGING_MIN_SEVERITY=INFO"

# 关键：ROS2 需要 source setup.bash，必须通过 bash -c 执行
ExecStart=/bin/bash -c "\
  source /opt/ros/humble/setup.bash && \
  source /opt/ros_ws/install/setup.bash && \
  ros2 run debug_ch5 simple_node"

# 崩溃后 5 秒重启
Restart=on-failure
RestartSec=5s

# 日志输出到 systemd journal
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**常见错误：用 EnvironmentFile 来 source**

```ini
# 错误写法 — EnvironmentFile 只能读取 KEY=VALUE 格式，不能执行 bash source
EnvironmentFile=/opt/ros/humble/setup.bash   # 不起作用！
```

ROS2 的 `setup.bash` 包含 `export`、条件判断等 bash 逻辑，必须在 bash 子进程里 source。

### 部署流程

```bash
# 1. 编译 ROS2 包
cd /opt/ros_ws
colcon build --packages-select debug_ch5
source install/setup.bash

# 2. 部署 service 文件
sudo cp /path/to/my_node.service.template /etc/systemd/system/simple_node.service

# 3. 让 systemd 重新读取 service 文件
sudo systemctl daemon-reload

# 4. 设置开机自启
sudo systemctl enable simple_node

# 5. 立即启动
sudo systemctl start simple_node

# 6. 查看运行状态
sudo systemctl status simple_node
```

预期 `status` 输出：
```
● simple_node.service - ROS2 simple_node heartbeat publisher
     Loaded: loaded (/etc/systemd/system/simple_node.service; enabled)
     Active: active (running) since ...
   Main PID: 12345 (bash)
```

### 日志查看

```bash
# 实时跟踪日志（类似 tail -f）
journalctl -u simple_node -f

# 查看最近 100 行
journalctl -u simple_node -n 100

# 查看某个时间段
journalctl -u simple_node --since "2024-01-01 10:00" --until "2024-01-01 11:00"

# 查看启动失败原因
journalctl -u simple_node -b -1   # 上次启动的日志（-b 0 是本次）
```

### 常用管理命令

```bash
sudo systemctl start simple_node      # 启动
sudo systemctl stop simple_node       # 停止
sudo systemctl restart simple_node    # 重启
sudo systemctl reload simple_node     # 重载配置（不停止进程，需节点支持）
sudo systemctl disable simple_node    # 取消开机自启（不停止当前运行）
sudo systemctl status simple_node     # 查看状态

# 查看所有 ROS2 相关服务
systemctl list-units --type=service | grep ros
```

---

## 5.3 多节点部署：Launch + systemd

对于需要启动多个节点的场景，用 `ros2 launch` 替代 `ros2 run`：

```ini
ExecStart=/bin/bash -c "\
  source /opt/ros/humble/setup.bash && \
  source /opt/ros_ws/install/setup.bash && \
  ros2 launch my_robot_pkg bringup.launch.py"
```

### 节点生命周期管理

`ros2_lifecycle` 提供受管节点（Managed Node）机制，节点可以在 `unconfigured → inactive → active` 状态间转换，systemd 只负责进程守护，节点状态由生命周期管理器控制：

```bash
ros2 lifecycle list /simple_node          # 查看可用状态转换
ros2 lifecycle set /simple_node activate  # 激活节点
```

---

## 练习步骤

```bash
# 1. 编译 ch5 节点
cd /your/ros_ws
cp -r ch5_deploy src/debug_ch5
colcon build --packages-select debug_ch5
source install/setup.bash

# 2. 手动验证节点运行
ros2 run debug_ch5 simple_node &
ros2 topic echo /heartbeat   # 应看到每秒一条消息
kill %1

# 3. 部署为 systemd 服务
# 编辑 my_node.service.template，将 debug_ch5 和路径改为实际值
sudo cp my_node.service.template /etc/systemd/system/simple_node.service
sudo systemctl daemon-reload
sudo systemctl start simple_node
sudo systemctl status simple_node

# 4. 验证日志
journalctl -u simple_node -f
# 应看到：SimpleNode started, publishing to /heartbeat
# 然后每秒：heartbeat #1, heartbeat #2, ...

# 5. 测试自动重启
sudo kill $(systemctl show -p MainPID simple_node | cut -d= -f2)
# 等 5 秒后查看状态，节点应自动重启
sudo systemctl status simple_node
```
