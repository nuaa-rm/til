# ROS 2 日志系统 (Logging) 新手指南

在 ROS 2 开发中，`printf` 或 `std::cout` 往往不足以满足复杂的调试需求。ROS 2 提供了一套强大且灵活的日志系统（基于 `rcutils` 和 `rclcpp`），它可以帮助你按日志级别过滤信息、控制打印频率，甚至自定义输出格式。

本文档主要面向 **C++ (rclcpp)** 开发者，介绍 ROS 2 日志系统的核心用法。

---

## 🚀 第一部分：基础日志宏

ROS 2 将日志分为 5 个严重级别（Severity Levels），从低到高依次为：

1. **DEBUG** (调试): 用于仅在调试时需要查看的详细信息。
2. **INFO** (信息): 用于报告系统的正常运行状态和关键事件。
3. **WARN** (警告): 用于报告可能出现问题或不符合预期的状况，但系统仍能继续运行。
4. **ERROR** (错误): 用于报告严重错误，某些功能可能已失效。
5. **FATAL** (致命): 用于报告导致节点崩溃或必须立即终止的灾难性错误。

### 基本语法格式

最常用的日志宏遵循类似于 `printf` 的格式化字符串语法：

```cpp
// 假设你在一个 Node 类的方法中，get_logger() 会获取当前节点的 Logger
RCLCPP_DEBUG(this->get_logger(), "这是一条调试信息，变量 x = %d", x);
RCLCPP_INFO(this->get_logger(), "节点已成功启动");
RCLCPP_WARN(this->get_logger(), "传感器数据延迟了 %f 秒", delay);
RCLCPP_ERROR(this->get_logger(), "无法连接到硬件设备！");
RCLCPP_FATAL(this->get_logger(), "内存分配失败，即将退出。");
```

---

## ⏱️ 第二部分：高级日志宏 (控制打印频率)

在循环或者高频回调函数（比如 100Hz 的定时器）中打印日志，如果每次都打印，终端会被瞬间刷屏。为了解决这个问题，ROS 2 提供了一系列带有后缀的高级宏。

*以下示例均以 `INFO` 级别为例，你同样可以将它们替换为 `DEBUG`, `WARN`, `ERROR` 等级别。*

### 1. 只打印一次 (`_ONCE`)
无论这行代码被执行多少次，日志只会在第一次执行时打印。
```cpp
RCLCPP_INFO_ONCE(this->get_logger(), "这个配置信息我只说一次：载入成功！");
```

### 2. 跳过第一次 (`_SKIPFIRST`)
有些时候第一次回调的数据是无效的或处于初始化状态，你想忽略它，从第二次开始才打印。
```cpp
RCLCPP_INFO_SKIPFIRST(this->get_logger(), "跳过第一次，这是后续的正常数据处理。");
```

### 3. 限制打印频率 / 节流 (`_THROTTLE`)
这是**最常用**的高级宏之一。它允许你限制特定日志的打印频率。
你需要传入一个时钟（通常是系统时钟或节点时钟）和一个以毫秒为单位的时间间隔。

```cpp
// 每隔 2000 毫秒（2秒）最多打印一次
RCLCPP_INFO_THROTTLE(
    this->get_logger(), 
    *this->get_clock(), 
    2000, 
    "当前机器人速度: %f (此信息每2秒打印一次)", speed
);
```

### 4. 条件打印 (`_EXPRESSION`)
只有当某个布尔表达式为 `true` 时才会打印。
```cpp
int error_code = get_status();
// 只有当 error_code 不为 0 时才打印
RCLCPP_ERROR_EXPRESSION(this->get_logger(), error_code != 0, "检测到错误码: %d", error_code);
```

### 5. 流式输出 (Stream 风格)
如果你不喜欢类似 C 语言的 `%d`、`%f` 占位符，ROS 2 也支持类似 `std::cout` 的 C++ 流式操作符。只需在宏名字后面加上 `_STREAM`：

```cpp
RCLCPP_INFO_STREAM(this->get_logger(), "当前坐标: X=" << x << ", Y=" << y);
RCLCPP_WARN_STREAM_THROTTLE(this->get_logger(), *this->get_clock(), 1000, "温度过高: " << temp << " °C");
```

---

## 🎛️ 第三部分：动态调整日志级别 (如何开启 DEBUG)

默认情况下，ROS 2 节点只会打印 `INFO` 及以上级别的日志。如果你在代码中写了 `RCLCPP_DEBUG`，正常运行时是看不到的。你需要显式地改变日志级别：

### 1. 命令行启动时设置
使用 `--ros-args --log-level` 参数可以非常方便地在启动时更改级别：
```bash
# 全局设置为 DEBUG 级别
ros2 run my_pkg my_executable --ros-args --log-level DEBUG

# 精确控制：只将名为 'my_node' 的节点设置为 DEBUG
ros2 run my_pkg my_executable --ros-args --log-level my_node:=DEBUG
```

### 2. 在 Launch 文件中配置
在 Launch 文件中，你可以通过 `ros_arguments` 传递相同的参数：
```python
Node(
    package='my_pkg',
    executable='my_executable',
    name='my_node',
    output='screen',
    ros_arguments=['--log-level', 'DEBUG']
)
```

### 3. 运行时动态修改 (超实用！)
如果你的机器人已经在运行，遇到突发 Bug，你不需要杀掉进程重启！ROS 2 允许你在运行时动态修改日志级别：
```bash
# 列出当前系统中所有节点的 logger
ros2 logger list

# 将运行中的 /my_node 节点的日志级别瞬间切换为 DEBUG
ros2 logger set /my_node DEBUG
```

---

## 🛠️ 第四部分：自定义日志输出格式 (包含文件名、行号、时间等)

默认情况下，ROS 2 的日志输出可能长这样：
`[INFO] [1680000000.123456789] [my_node]: 节点已启动`

如果你希望在日志中**显示打印这行代码的源文件名称、具体的代码行号，或者把时间戳转换成人类可读的日期时间格式**，你不需要修改任何 C++ 代码！ROS 2 提供了一个环境变量 `RCUTILS_CONSOLE_OUTPUT_FORMAT` 来控制全局输出格式。

### 1. 支持的格式化占位符

- `{severity}`: 日志级别 (如 INFO, ERROR)
- `{name}`: Logger 的名称 (通常是节点名)
- `{message}`: 你实际写的日志内容
- `{time}`: 自 Epoch 以来的时间戳 (秒和纳秒)
- `{time_as_sec}`: 自 Epoch 以来的时间戳 (浮点秒)
- `{date_time_with_ms}`: **人类可读的本地时间**，精确到毫秒 (例如: `2023-10-25 14:30:15.123`)
- `{file_name}`: **调用日志宏的源文件绝对路径**
- `{function_name}`: **调用日志宏的函数名**
- `{line_number}`: **调用日志宏的代码行号**

### 2. 如何使用？

你只需要在运行你的 ROS 2 节点之前（或者在 `~/.bashrc` 中）设置这个环境变量即可。

**示例 A：极简格式 (只显示级别、名字和内容)**
```bash
export RCUTILS_CONSOLE_OUTPUT_FORMAT="[{severity}] [{name}]: {message}"
# 效果: [INFO] [my_node]: 节点已启动
```

**示例 B：终极调试格式 (包含人类可读时间、文件名、行号、函数名) 🎉**
如果你需要精准定位问题，推荐使用这个配置：
```bash
export RCUTILS_CONSOLE_OUTPUT_FORMAT="[{date_time_with_ms}] [{severity}] [{name}] [{file_name}:{line_number} ({function_name})]: {message}"
```
**实际输出效果：**
`[2023-10-25 14:30:15.123] [INFO] [my_node] [/home/user/ros2_ws/src/my_pkg/src/my_node.cpp:42 (timer_callback)]: 节点已启动`

### 3. 在 Launch 文件中配置
如果你使用 Python Launch 文件启动节点，可以在 launch 文件中注入这个环境变量，这样就不需要每次手动 `export` 了：

```python
from launch import LaunchDescription
from launch_ros.actions import Node
from launch.actions import SetEnvironmentVariable

def generate_launch_description():
    return LaunchDescription([
        # 设置全局日志格式
        SetEnvironmentVariable(
            name='RCUTILS_CONSOLE_OUTPUT_FORMAT',
            value='[{date_time_with_ms}] [{severity}] [{name}] [{file_name}:{line_number}]: {message}'
        ),
        
        Node(
            package='my_pkg',
            executable='my_executable',
            name='my_node',
            output='screen'
        )
    ])
```

### 4. 开启彩色日志 (针对 Launch 文件)
很多开发者会发现，直接用 `ros2 run` 启动时日志是有颜色的，但通过 `ros2 launch` 启动时，所有的日志都变成了单调的白色。这是因为 `rcutils` 默认在检测到非 TTY 输出时会关闭颜色。

要强制开启彩色日志，请设置以下环境变量：
```bash
export RCUTILS_COLORIZED_OUTPUT=1
```
你同样可以把它写进 `~/.bashrc` 或者在 Launch 文件中使用 `SetEnvironmentVariable` 注入。

---

## 💾 第五部分：日志持久化 (保存到文件)

在调试复杂的系统或进行实车测试时，屏幕上的日志往往稍纵即逝。将日志保存到文件中以便后续分析是非常重要的。

### 1. 默认保存路径
当你使用 `ros2 launch` 启动节点时，ROS 2 会自动将日志保存到本地磁盘。
- **默认路径**：`~/.ros/log/`
- **组织方式**：每个启动周期都会创建一个以时间戳命名的文件夹（或包含一个 `latest` 软连接指向最近一次运行的日志）。
- **查看方法**：
  ```bash
  # 查看最近一次运行的日志列表
  ls -l ~/.ros/log/latest
  ```

### 2. 在 Launch 文件中配置输出
在 Launch 文件中，你可以通过 `output` 参数控制日志的去向：

- `output='screen'`: 日志只打印到终端屏幕。
- `output='log'`: 日志只保存到文件，不显示在屏幕上（适合后台运行）。
- `output='both'`: **(推荐)** 既打印到屏幕，又保存到文件。

```python
Node(
    package='my_pkg',
    executable='my_executable',
    output='both'  # 同时输出到屏幕和文件
)
```

### 3. 修改日志保存位置
如果你希望将日志保存到特定的位置（例如挂载的外接硬盘），可以设置环境变量 `ROS_LOG_DIR`：

```bash
export ROS_LOG_DIR=/path/to/your/custom/log/folder
```

### 4. 手动重定向 (针对 `ros2 run`)
如果你直接使用 `ros2 run` 启动节点，日志默认只会在屏幕打印。你可以使用标准的 Linux 重定向操作：

```bash
# 将标准输出和错误输出都保存到 my_node.log
ros2 run my_pkg my_executable > my_node.log 2>&1
```

---
**总结：** 熟练掌握上述各种宏以及格式化环境变量，不仅能让你的终端输出干净整洁，更能在排查 Bug 时为你提供像精确制导导弹一样的时间和位置信息。同时，学会查找本地日志文件，是进阶为高级 ROS 开发者处理复杂问题的必经之路。