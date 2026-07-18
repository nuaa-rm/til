# 第二章：ROS2 调试技巧

## 概述

ROS2 调试的核心思路是"让数据可见"。本章介绍三层工具：Foxglove Studio（波形可视化 + 自定义脚本）、visualization_msgs（在 3D 空间中标注调试信息）、ROS2 CLI（快速诊断节点/话题状态）。

练习节点发布两路正弦信号作为李萨如图的 X/Y 轴，3D Marker 的轨迹**直接来自这两个话题的值**，不做任何独立计算，确保"可视化 = 数据"。

练习文件：`ch2_ros2_debug/talker_with_markers.cpp`

---

## 2.0 练习节点说明

节点名：`/lissajous_talker`，发布频率 50 Hz。

| 话题 | 类型 | 内容 |
|------|------|------|
| `/debug/lissajous/x` | `std_msgs/Float64` | X 轴信号：`amp_x * sin(2π·freq_x·t + phase_x)` |
| `/debug/lissajous/y` | `std_msgs/Float64` | Y 轴信号：`amp_y * sin(2π·freq_y·t + phase_y)` |
| `/debug/markers` | `visualization_msgs/MarkerArray` | 李萨如轨迹线 + 当前位置球 + X/Y 轴箭头 |

**3D Marker 与话题的关系**：marker 的坐标直接取自上面两个话题发布的值，改变参数后话题和 marker 同步变化，Plot 面板与 3D 面板显示的是同一份数据。

---

## 2.1 Foxglove Studio

### 连接 ROS2

```bash
sudo apt install ros-$ROS_DISTRO-foxglove-bridge
ros2 launch foxglove_bridge foxglove_bridge_launch.xml
# 默认监听 ws://localhost:8765
```

Foxglove Studio → Open Connection → **Rosbridge WebSocket** → `ws://localhost:8765`

---

### Plot 面板

**推荐布局：**

1. 添加 Plot 面板，加入以下系列：
   ```
   /debug/lissajous/x.data                      # X 轴原始信号
   /debug/lissajous/y.data                      # Y 轴原始信号
   /debug/lissajous/x.data@derivative           # X 轴瞬时角速度
   /debug/lissajous/x.data@moving_average{n=10} # 平滑后的 X 信号
   ```

2. 同时观察 x/y 两条曲线的频率比，即可在脑中预测李萨如图的形状。

**消息路径语法：**

```
/topic.field                    基本字段
/topic.field@derivative         实时求导（差分/时间步长）
/topic.field@moving_average{n=N} 滑动平均，N 为窗口帧数
```

---

### `@` 操作符

#### `@derivative`

```
/debug/lissajous/x.data@derivative
```

对时间序列求一阶差分导数，得到变化率。此处可观察到 X 信号的角速度为余弦波形，与理论 `2π·freq_x·cos(...)` 吻合。

#### `@moving_average{n=N}`

```
/debug/lissajous/x.data@moving_average{n=20}
```

对最近 N 帧求均值。加噪声时对比原始信号和平滑信号，评估噪声强度与响应延迟的权衡。

---

### User Scripts

位置：左侧面板列表 → **User Scripts**（或 Add Panel → User Scripts）

将以下脚本粘贴进去，可实时计算当前点到原点的距离并检测是否超出设定半径：

```typescript
export const inputs = ["/debug/lissajous/x", "/debug/lissajous/y"];
export const output  = "/user_scripts/lissajous_info";

let lastX = 0, lastY = 0;

export default function script(event, variables) {
  if (event.topic === "/debug/lissajous/x") { lastX = event.message.data; return; }
  if (event.topic === "/debug/lissajous/y") { lastY = event.message.data; return; }
  const r = Math.sqrt(lastX * lastX + lastY * lastY);
  const threshold = variables.alert_radius ?? 1.2;
  return { x: lastX, y: lastY, radius: r, outside: r > threshold };
}
```

配合 Variables 面板添加变量 `alert_radius = 1.2`，在 Plot 面板订阅 `/user_scripts/lissajous_info.outside` 查看超界标志。

---

### 3D 面板配置

1. 添加 **3D** 面板
2. 设置 **Fixed frame** 为 `map`
3. 订阅 `/debug/markers`（通常自动发现）
4. 可见：
   - 渐变色轨迹线（旧点蓝色透明 → 新点白色不透明）
   - 黄色球：当前位置（"画笔笔尖"）
   - 红色箭头：当前 X 值的轴向指示
   - 绿色箭头：当前 Y 值的轴向指示

---

## 2.2 李萨如参数调节

通过 `ros2 param set` 实时改变图形，**无需重启节点**，Foxglove 3D 面板立即响应。

### 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `freq_x` | `1.0` | X 轴信号频率（Hz） |
| `freq_y` | `2.0` | Y 轴信号频率（Hz） |
| `phase_x` | `0.0` | X 轴初相位（弧度） |
| `phase_y` | `π/2 ≈ 1.5708` | Y 轴初相位（弧度） |
| `amp_x` | `1.0` | X 轴幅值（米） |
| `amp_y` | `1.0` | Y 轴幅值（米） |
| `trail_length` | `200` | 轨迹保留点数 |

### 经典预设

```bash
# 圆形（freq 比 1:1，相位差 π/2）
ros2 param set /lissajous_talker freq_x 1.0
ros2 param set /lissajous_talker freq_y 1.0
ros2 param set /lissajous_talker phase_y 1.5708

# 8字形 / 竖椭圆（freq 比 1:2，相位差 π/2）—— 默认
ros2 param set /lissajous_talker freq_x 1.0
ros2 param set /lissajous_talker freq_y 2.0
ros2 param set /lissajous_talker phase_y 1.5708

# 三叶结（freq 比 1:3）
ros2 param set /lissajous_talker freq_x 1.0
ros2 param set /lissajous_talker freq_y 3.0
ros2 param set /lissajous_talker phase_y 1.5708

# 蝴蝶结（freq 比 2:1，相位差 0）
ros2 param set /lissajous_talker freq_x 2.0
ros2 param set /lissajous_talker freq_y 1.0
ros2 param set /lissajous_talker phase_y 0.0

# 复杂结（freq 比 3:4，相位差 π/4）
ros2 param set /lissajous_talker freq_x 3.0
ros2 param set /lissajous_talker freq_y 4.0
ros2 param set /lissajous_talker phase_y 0.7854

# 五角星（freq 比 5:4，相位差 π/8）
ros2 param set /lissajous_talker freq_x 5.0
ros2 param set /lissajous_talker freq_y 4.0
ros2 param set /lissajous_talker phase_y 0.3927
```

**判断规律：**
- freq 比 `m:n`（最简整数比）→ 曲线有 m 个 X 方向切点，n 个 Y 方向切点
- 相位差 = π/2 时图形最"圆润"；相位差 = 0 时图形退化为对角线
- `trail_length` 调大可看到完整周期（李萨如曲线周期 = `1/gcd(freq_x, freq_y)` 秒）

---

## 2.3 visualization_msgs 调试标记

### Marker 基本用法

```cpp
#include <visualization_msgs/msg/marker.hpp>
#include <visualization_msgs/msg/marker_array.hpp>

auto marker = visualization_msgs::msg::Marker();
marker.header.frame_id = "map";
marker.header.stamp = node->now();
marker.ns = "debug";
marker.id = 0;
marker.action = visualization_msgs::msg::Marker::ADD;
```

### Marker 类型速查

| 类型常量 | 形状 | 典型用途 |
|----------|------|---------|
| `SPHERE` | 球 | 标注关键点、当前位置 |
| `ARROW` | 箭头 | 方向、速度、轴向指示 |
| `LINE_STRIP` | 折线 | 路径、轨迹（本章使用） |
| `LINE_LIST` | 线段组 | 网格、边界框 |
| `CUBE` | 立方体 | 障碍物包围盒 |
| `TEXT_VIEW_FACING` | 文字 | 调试标注 |

### `LINE_STRIP` 彩色渐变（本章核心用法）

```cpp
visualization_msgs::msg::Marker line;
line.type   = visualization_msgs::msg::Marker::LINE_STRIP;
line.scale.x = 0.015;  // 线宽

for (size_t i = 0; i < trail.size(); ++i) {
    geometry_msgs::msg::Point p;
    p.x = trail[i].first;
    p.y = trail[i].second;
    line.points.push_back(p);

    // 必须与 points 等长，逐点着色
    std_msgs::msg::ColorRGBA c;
    float ratio = static_cast<float>(i) / (trail.size() - 1);
    c.r = ratio; c.g = 0.6f + 0.4f * ratio; c.b = 1.0f;
    c.a = 0.2f + 0.8f * ratio;  // 旧点透明，新点不透明
    line.colors.push_back(c);
}
```

### `id` 管理

- 同 `ns` 下相同 `id` 的 ADD 会更新旧 marker（本章每帧覆盖 id=0 的轨迹线）
- 设置 `lifetime = rclcpp::Duration::from_seconds(0)` 表示永久显示，直到被覆盖或 DELETE
- 需要清空所有 marker 时发送 `action = DELETEALL`

---

## 2.4 ROS2 CLI 快速诊断

```bash
ros2 node list
ros2 node info /lissajous_talker        # 查看发布/订阅/参数列表

ros2 topic hz /debug/lissajous/x       # 验证 50 Hz
ros2 topic echo /debug/lissajous/x     # 查看实时值

ros2 param list /lissajous_talker      # 列出所有可调参数
ros2 param get /lissajous_talker freq_y
ros2 param set /lissajous_talker freq_y 3.0

ros2 doctor                            # 全局健康检查
rqt_graph                              # 可视化节点连接图
```

---

## 编译与运行

```bash
# ROS2 工作空间根目录
cp -r ch2_ros2_debug src/debug_ch2
colcon build --packages-select debug_ch2
source install/setup.bash

# 启动 Foxglove bridge
ros2 launch foxglove_bridge foxglove_bridge_launch.xml &

# 启动练习节点
ros2 run debug_ch2 talker_with_markers
```

然后在 Foxglove Studio：
1. 连接 `ws://localhost:8765`
2. 3D 面板订阅 `/debug/markers`，Fixed frame 设为 `map`
3. Plot 面板添加 `/debug/lissajous/x.data` 和 `/debug/lissajous/y.data`
4. 用 `ros2 param set` 切换预设，观察 3D 曲线实时变化
