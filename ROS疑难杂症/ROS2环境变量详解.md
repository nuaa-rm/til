# ROS 2 常用环境变量详解指南

在 ROS 2 中，环境变量扮演着极其重要的角色。它们可以控制节点的底层通信机制、网络可见性、日志格式、路径解析等核心行为，而无需修改任何代码。

本文档汇总并详细解释了 ROS 2 开发中最常用、最重要的环境变量，帮助你更全面地掌控 ROS 2 系统。

---

## 🌐 1. 网络与通信隔离 (Domain & Network)

### `ROS_DOMAIN_ID`
这是 ROS 2 中**最常用**的环境变量。它用于隔离不同的 ROS 2 网络。默认值为 `0`。
如果在同一局域网下有多个开发者同时运行 ROS 2，或者有多个独立的机器人编队，为了防止他们的节点互相干扰、互相订阅，你需要为每一组分配不同的 Domain ID。
- **有效范围**：`0` 到 `101`（或更高，取决于具体的 RMW 和操作系统网络配置，但建议在 0-101 之间）。
- **用法**：
  ```bash
  export ROS_DOMAIN_ID=42
  ```

### `ROS_LOCALHOST_ONLY`
这是一个非常实用的安全/调试变量。设置为 `1` 时，ROS 2 的所有通信将严格限制在本地环回接口（localhost/127.0.0.1）内，节点将完全忽略局域网内的其他设备。
- **场景**：在咖啡厅等公共 Wi-Fi 下开发、或者仅在单机上进行仿真测试时，强烈建议开启。
- **用法**：
  ```bash
  export ROS_LOCALHOST_ONLY=1
  ```

### `ROS_DISCOVERY_SERVER`
针对 Fast DDS（ROS 2 默认的中间件），当你的网络环境不支持多播（Multicast）或者跨网段（如 VPN 环境）时，传统的组播发现机制会失效。你可以设置一个发现服务器（Discovery Server），并将此环境变量指向该服务器的 IP 和端口。
- **用法**：
  ```bash
  export ROS_DISCOVERY_SERVER="192.168.1.100:11811"
  ```

---

## 🔌 2. 中间件与底层实现 (Middleware & RMW)

### `RMW_IMPLEMENTATION`
ROS 2 的核心优势之一是它不绑定具体的 DDS 实现。你可以通过这个变量在不同的 DDS 供应商之间切换，而不需要重新编译你的代码（前提是你安装了相应的 RMW 包）。
- **常见值**：
  - `rmw_fastrtps_cpp` (默认，Fast DDS)
  - `rmw_cyclonedds_cpp` (Eclipse Cyclone DDS，在多播不稳定的 Wi-Fi 下表现通常更好)
  - `rmw_connextdds` (RTI Connext DDS)
- **用法**：
  ```bash
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  ```

### `CYCLONEDDS_URI` (针对 Cyclone DDS)
当 `RMW_IMPLEMENTATION` 设置为 Cyclone DDS 时，可以通过该环境变量指向一个 XML 配置文件。在这里，你可以详细调优网络组播地址、网卡接口绑定（绑定特定的物理网卡）、QoS 策略等进阶设置。
- **用法**：
  ```bash
  export CYCLONEDDS_URI=file:///path/to/cyclonedds.xml
  ```

### `FASTRTPS_DEFAULT_PROFILES_FILE` (针对 Fast DDS)
当使用默认的 Fast DDS 时，指定配置文件的路径。如果你需要禁用共享内存通信（SHM，跨宿主机与 Docker 时常引发问题），或者手动配置复杂的发现机制，就需要它。
- **用法**：
  ```bash
  export FASTRTPS_DEFAULT_PROFILES_FILE=/path/to/fastdds_profile.xml
  ```

---

## 📝 3. 日志与终端输出 (Logging)

### `RCUTILS_CONSOLE_OUTPUT_FORMAT`
控制终端日志的输出格式。你可以注入时间戳、文件名、行号等信息。
- **常用配置**：
  ```bash
  export RCUTILS_CONSOLE_OUTPUT_FORMAT="[{date_time_with_ms}] [{severity}] [{name}] [{file_name}:{line_number}]: {message}"
  ```

### `RCUTILS_COLORIZED_OUTPUT`
强制开启终端日志的彩色输出。在 `ros2 launch` 中，如果发现日志变成了单调的白色，可以通过开启此变量恢复颜色。
- **用法**：
  ```bash
  export RCUTILS_COLORIZED_OUTPUT=1
  ```

### `ROS_LOG_DIR`
自定义 ROS 2 日志文件的保存目录。默认情况下，日志会保存在 `~/.ros/log/` 目录下。
- **用法**：
  ```bash
  export ROS_LOG_DIR=/path/to/my/custom/log_dir
  ```

### `RCUTILS_LOGGING_USE_STDOUT`
默认情况下，ROS 2 的 DEBUG 和 INFO 级别日志输出到 `stdout`，而 WARN、ERROR、FATAL 输出到 `stderr`。设置为 `1` 时，所有级别的日志将强制统一输出到 `stdout`。这在某些自动化测试或日志收集脚本中处理输出时非常有用。

### `RCUTILS_LOGGING_BUFFERED_STREAM`
控制日志流的缓冲机制。设置为 `0`（禁用缓冲）或 `1`（开启缓冲）。
- **避坑提示**：在使用 Docker 容器或者 `systemd` 后台服务运行 ROS 2 Python 节点时，你可能会发现终端半天没有输出（被缓冲“吃掉”了）。通过设置 `export RCUTILS_LOGGING_BUFFERED_STREAM=1`（或禁用 Python 缓冲 `PYTHONUNBUFFERED=1`）可以解决这种“日志被吞”的错觉。

---

## 📂 4. 工作空间与路径解析 (Workspace & Paths)

每次你 `source /opt/ros/humble/setup.bash` 或者 `source install/setup.bash` 时，实际上就是在背后修改以下这些路径变量。

### `AMENT_PREFIX_PATH`
ROS 2 的 Ament 构建系统通过这个变量来定位各个 package 的安装前缀（类似于标准的 `CMAKE_PREFIX_PATH`）。当你找不到某个包的 launch 文件或依赖时，检查这个变量通常能发现问题。
- **查看当前路径**：
  ```bash
  echo $AMENT_PREFIX_PATH
  ```

### `ROS_PACKAGE_PATH`
虽然在 ROS 1 中更常用，但在某些 ROS 2 兼容层或特定工具中仍会用到，用于指定包的搜索路径。

### `PYTHONPATH`
ROS 2 的很多工具和节点是用 Python 编写的。`source` 工作空间会将你编译出的 Python 库路径追加到 `PYTHONPATH` 中，这样你的节点才能 `import` 其他包的 Python 模块。

### `LD_LIBRARY_PATH` (Linux) / `DYLD_LIBRARY_PATH` (macOS)
包含 ROS 2 及其依赖的动态链接库（`.so` 文件）路径。如果运行 C++ 节点时报错说找不到 `libxxx.so`，通常是因为这个变量没有正确包含该库的路径（即你忘记了 source 工作空间）。

---

## 🛡️ 5. 安全与加密 (Security)

ROS 2 支持 SROS2，可以对 DDS 层的通信进行身份验证和加密。

### `ROS_SECURITY_ENABLE`
开启或关闭 ROS 2 的安全特性。
- **用法**：`export ROS_SECURITY_ENABLE=true`

### `ROS_SECURITY_STRATEGY`
当开启安全特性时，如果缺少安全凭证，节点是直接报错退出，还是退化为不加密的通信。
- **有效值**：`Enforce` (强制，无凭证则报错) 或 `Permissive` (宽容，尝试加密，失败则明文)。

### `ROS_SECURITY_KEYSTORE`
指定安全证书（Keystore）的存放路径。
- **用法**：`export ROS_SECURITY_KEYSTORE=/path/to/your/keystore`

---

## ℹ️ 6. 系统与版本信息 (System Info)

### `ROS_VERSION` 和 `ROS_DISTRO`
当你成功 `source` ROS 2 核心环境（如 `/opt/ros/humble/setup.bash`）后，系统会自动注入这两个变量。`ROS_VERSION` 的值为 `2`，`ROS_DISTRO` 的值为你当前使用的版本代号（如 `foxy`, `humble`, `jazzy` 等）。
- **诊断利器**：如果在终端里输入 `echo $ROS_DISTRO` 没有任何输出，说明你当前终端**根本没有加载 ROS 环境**！此外，在编写兼容多版本的 `.sh` 脚本或 Launch 文件时，常常依赖这两个变量做条件判断。

### `ROS_AUTOMATIC_DISCOVERY_RANGE` (较新版本可用, 如 Iron / Jazzy)
这是一个较新的环境变量，用来极大简化多网卡/跨网段环境下的发现范围配置。这比直接去手写复杂的 XML 配置文件要简单得多。
- **有效值**：`LOCALHOST` (仅限本机)、`SUBNET` (当前所在子网) 或 `SYSTEM_DEFAULT` (系统默认，通常意味着允许组播穿透）。

---

## 💡 最佳实践建议

1. **不要把所有东西都塞进 `~/.bashrc`**：除了像 `ROS_DOMAIN_ID` 或者 `RCUTILS_COLORIZED_OUTPUT` 这种你希望全局永久生效的变量，其他的（比如 `RMW_IMPLEMENTATION`）建议只在当前终端按需 `export`，避免日后排查问题时产生混淆。
2. **Launch 文件注入**：对于特定项目必须依赖的环境变量（比如指定特定的 `ROS_DISCOVERY_SERVER`），最好使用 Launch 文件的 `SetEnvironmentVariable` 动作将其封装在代码中，而不是指望每个用户在运行前都手动设置。