# ROS 2 Launch 文件详细指南 (基础与进阶)

在 ROS 2 开发中，随着系统的复杂化，手动用 `ros2 run` 一个个启动节点变得不再现实。ROS 2 提供了一个强大的启动系统（Launch System），允许你通过编写脚本同时启动多个节点、配置参数、重映射话题，并处理节点间的依赖关系。

虽然 ROS 2 支持 XML 和 YAML 格式的 launch 文件，但 **Python 格式** 是官方首推且功能最强大的格式，本文档将专门介绍 Python Launch 文件的用法。

---

## 🟢 第一部分：基础用法 (单节点启动)

### 1. Launch 文件的基本结构
每个 Python launch 文件必须包含一个 `generate_launch_description()` 函数，它返回一个 `LaunchDescription` 对象。

```python
from launch import LaunchDescription
from launch_ros.actions import Node

def generate_launch_description():
    return LaunchDescription([
        # 在这里添加你要启动的 Action (比如 Node)
    ])
```

### 2. 启动一个简单的节点
这是最基础的 `Node` Action，等价于在终端输入 `ros2 run my_pkg my_node`。

```python
from launch import LaunchDescription
from launch_ros.actions import Node

def generate_launch_description():
    my_node = Node(
        package='my_pkg',           # 包名
        executable='my_node',       # 可执行文件名 (C++的二进制文件或Python脚本名)
        name='custom_node_name',    # (可选) 覆盖节点在代码中定义的名字
        output='screen'             # 将日志输出到屏幕
    )
    
    return LaunchDescription([my_node])
```

---

## 🟡 第二部分：进阶配置 (参数、重映射与环境变量)

### 1. 话题与服务的重映射 (Remapping)
当你使用开源包（如雷达驱动）时，它默认发布的话题名可能叫 `/scan`，但你的导航包订阅的是 `/lidar_scan`。无需改代码，通过重映射即可连接它们。

```python
Node(
    package='turtlesim',
    executable='turtlesim_node',
    name='sim',
    remappings=[
        ('/turtle1/cmd_vel', '/my_cmd_vel'),  # 将原本的 cmd_vel 映射为 my_cmd_vel
        ('/turtle1/pose', '/robot_pose')
    ]
)
```

### 2. 加载参数 (Parameters & YAML)
你可以直接在代码中传入字典参数，也可以加载实现准备好的 YAML 参数文件。

```python
import os
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node

def generate_launch_description():
    # 动态获取 package 的安装路径 (极其常用的写法！)
    my_pkg_dir = get_package_share_directory('my_pkg')
    config_file = os.path.join(my_pkg_dir, 'config', 'params.yaml')

    node = Node(
        package='my_pkg',
        executable='my_node',
        parameters=[
            {'use_sim_time': True},  # 传入字典 (单个参数)
            config_file              # 传入 YAML 配置文件路径
        ]
    )
    return LaunchDescription([node])
```

### 3. 设置环境变量
有时特定的节点需要特定的环境变量（如 DDS 配置、日志格式等）。你可以使用 `SetEnvironmentVariable` 为整个 Launch 上下文设置变量，也可以使用 `Node` 的 `env` 字典仅为该节点设置。

```python
from launch.actions import SetEnvironmentVariable

# 全局设置环境变量 (影响之后启动的所有节点)
set_env = SetEnvironmentVariable(
    name='RCUTILS_CONSOLE_OUTPUT_FORMAT',
    value='[{severity}] [{name}]: {message}'
)

# 局部设置 (仅限此节点)
node = Node(
    package='my_pkg',
    executable='my_node',
    env={'ROS_DOMAIN_ID': '42'}
)
```

---

## 🔴 第三部分：高级用法 (传参、条件控制与嵌套)

### 1. 外部传参 (Launch Arguments)
你希望在终端使用 `ros2 launch my_pkg run.launch.py mode:=debug` 来控制程序的行为。

你需要两样东西：
1. `DeclareLaunchArgument`: 声明这个参数（相当于注册这个变量）。
2. `LaunchConfiguration`: 在后续代码中读取这个参数的值。

```python
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

def generate_launch_description():
    # 1. 声明一个从命令行传入的参数，带默认值
    mode_arg = DeclareLaunchArgument(
        'mode', default_value='release', description='运行模式：debug 或 release'
    )
    
    # 2. 获取该参数的值
    mode_val = LaunchConfiguration('mode')

    node = Node(
        package='my_pkg',
        executable='my_node',
        parameters=[{'run_mode': mode_val}] # 将命令行参数转递给节点的 ROS 参数
    )
    
    return LaunchDescription([mode_arg, node])
```

### 2. 嵌套引入其他 Launch 文件 (Include)
不要把所有节点塞进一个巨大的 launch 文件中。你应该按模块编写，然后在一个主 launch 文件中 `Include` 它们。

```python
import os
from ament_index_python.packages import get_package_share_directory
from launch.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource

def generate_launch_description():
    nav2_pkg_dir = get_package_share_directory('nav2_bringup')
    
    # 引入外部的 launch 文件
    nav2_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(nav2_pkg_dir, 'launch', 'navigation_launch.py')
        ),
        # 可以向嵌套的 launch 文件传递参数
        launch_arguments={'use_sim_time': 'true'}.items()
    )
    
    return LaunchDescription([nav2_launch])
```

### 3. 条件判断执行 (Conditionals)
只有当满足特定条件（通常是依据命令行传入的参数）时，才启动某个节点或执行某个动作。常用的有 `IfCondition` 和 `UnlessCondition`（如果不）。

```python
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration

def generate_launch_description():
    use_rviz_arg = DeclareLaunchArgument('use_rviz', default_value='true')
    use_rviz_val = LaunchConfiguration('use_rviz')

    rviz_node = Node(
        package='rviz2',
        executable='rviz2',
        # 只有当 use_rviz_val 为 'true' 或 '1' 时才启动
        condition=IfCondition(use_rviz_val) 
    )
    
    return LaunchDescription([use_rviz_arg, rviz_node])
```

---

## ☠️ 第四部分：终极杀器 (事件处理与生命周期)

### 1. 事件处理 (Event Handlers)
有时候节点的启动有严格的顺序要求。比如：“必须等建图节点崩溃退出后，再启动数据保存节点”。

使用 `RegisterEventHandler` 可以监听进程的退出、死亡或特定输出。

```python
from launch.actions import RegisterEventHandler, LogInfo
from launch.event_handlers import OnProcessExit

def generate_launch_description():
    node_A = Node(package='my_pkg', executable='node_a')
    node_B = Node(package='my_pkg', executable='node_b')

    # 当 node_A 退出后，执行 node_B 和打印一句话
    event_handler = RegisterEventHandler(
        event_handler=OnProcessExit(
            target_action=node_A,
            on_exit=[
                LogInfo(msg="节点A已退出，现在启动节点B！"),
                node_B
            ]
        )
    )

    return LaunchDescription([node_A, event_handler])
```

### 2. OpaqueFunction (在 Launch 阶段执行 Python 逻辑)
Launch 描述是**声明式**的（它先构建一个图，然后统一执行）。如果你需要**在 Launch 解析阶段根据参数去读取文件或者执行复杂的 Python 逻辑**（比如拼接很长的字符串或者判断某个目录存不存在），普通的 `LaunchConfiguration` 是做不到的。你需要使用 `OpaqueFunction`。

> 这是一个高级特性，主要解决 `LaunchConfiguration` 不能直接当作 Python 字符串参与逻辑运算的问题。它会将 context 传递进你的回调函数中，让你获得参数的真实值。

---

## 💡 最佳实践总结

1. **多用 `get_package_share_directory`**：永远不要在 launch 文件里写绝对路径（如 `/home/user/ros2_ws/...`），要通过包名动态寻找路径。
2. **职责单一**：一个传感器写一个 launch，算法模块写一个 launch，最后用一个 `bringup.launch.py` 把它们全都 `Include` 进来。
3. **暴露核心配置**：通过 `DeclareLaunchArgument` 将关键配置（如 `use_sim_time`, `map_path`）暴露到命令行，方便其他开发者使用。