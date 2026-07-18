# 第四章：性能优化与火焰图

## 概述

本章介绍如何用 CLion 内置 Profiler 和 Linux `perf` 采集 CPU 火焰图，找到程序的真正热点，然后针对性地优化。核心技能是读懂火焰图，而不是盲目猜测哪里慢。

练习文件：`ch4_profiling/slow_processor.cpp`

---

## 4.1 为什么需要 Profiler

**错误的优化流程：** 凭直觉猜哪里慢 → 优化猜到的地方 → 效果不明显

**正确的优化流程：** Profiler 采样 → 火焰图定位真正热点 → 针对热点优化 → 再次采样对比

90% 的 CPU 时间通常集中在 10% 的代码里（二八定律的极端版本）。Profiler 的价值是找到那 10%。

---

## 4.2 CLion 内置 Profiler

### 前提条件

Linux 下 CLion Profiler 依赖 `perf`：

```bash
sudo apt install linux-tools-common linux-tools-$(uname -r)
# 允许非 root 用户采样
echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid
```

### 使用步骤

1. 在 CLion 中选择要分析的 Run Configuration（选 `slow_processor`，编译选项为 `-g -O0`）
2. 菜单 **Run → Profile '...'**（或工具栏的火焰图按钮）
3. 程序运行并完成后，CLion 自动打开 Profiler 结果面板
4. 面板有三个视图标签：
   - **Flame Graph**（火焰图）
   - **Call Tree**（调用树，按函数统计）
   - **Method List**（热点函数列表，按自身时间排序）

### 读火焰图

```
main
├── benchmark (multiply_slow wrapper)
│   └── multiply_slow ████████████████████████████   <- 最宽，是热点
│       └── std::vector::operator[]  ████
└── benchmark (vector_norm_slow wrapper)
    └── vector_norm_slow ████████████   <- 第二热点
        └── vector_norm_slow (inner loop)
```

**关键规则：**
- **X 轴宽度 = CPU 时间占比**，不是执行顺序
- **Y 轴 = 调用深度**，顶部是叶函数（真正消耗 CPU 的地方）
- **目标：最宽的"平顶"色块**，即叶节点宽但子节点少的函数
- 点击色块 → 直接跳转到对应源码行

### 识别热点的三种模式

| 模式 | 火焰图特征 | 典型原因 |
|------|-----------|---------|
| 宽平顶 | 某函数本身很宽，子节点少 | 算法复杂度问题，如 O(n²) 循环 |
| 高瘦塔 | 深层调用链，每层都很窄 | 不必要的间接调用、虚函数开销 |
| 分散小块 | 很多小函数各占一点 | 内存分配碎片、频繁拷贝 |

---

## 4.3 Linux perf 命令行采样

```bash
# 编译（带 debug 符号，关闭优化）
cd ch4_profiling/build
cmake .. && make slow_processor

# 采样（-g 捕获调用栈，-F 99 表示每秒 99 次采样）
sudo perf record -g -F 99 ./slow_processor

# 生成火焰图（需要 FlameGraph 工具）
git clone https://github.com/brendangregg/FlameGraph /tmp/FlameGraph
sudo perf script | /tmp/FlameGraph/stackcollapse-perf.pl | \
    /tmp/FlameGraph/flamegraph.pl > flame.svg

# 用浏览器打开
xdg-open flame.svg
```

**采样已运行进程（适合 ROS2 节点）：**
```bash
# 找到节点 PID
ros2 node list
ps aux | grep my_node

sudo perf record -g -p <PID> -- sleep 10   # 采样 10 秒
```

---

## 4.4 分析练习文件中的三个热点

### 热点 1：cache-unfriendly 矩阵乘法

`slow_processor.cpp:28` — `multiply_slow`：
```cpp
for (int i = 0; i < n; ++i)
    for (int j = 0; j < m; ++j)        // 外层遍历 B 的列
        for (int p = 0; p < k; ++p)
            C[i][j] += A[i][p] * B[p][j];   // B[p][j] 跨行访问，cache miss
```

火焰图中 `std::vector::operator[]` 会占据大量时间，说明是内存访问瓶颈。

**修复（交换循环顺序）：**
```cpp
for (int i = 0; i < n; ++i)
    for (int p = 0; p < k; ++p)        // 中间层遍历 p
        for (int j = 0; j < m; ++j)
            C[i][j] += A[i][p] * B[p][j];   // B[p][j] 现在是顺序访问
```

同样的 O(n³) 算法，只改循环顺序，实测 2-5x 加速。

### 热点 2：O(n²) 范数计算

`slow_processor.cpp:39` — `vector_norm_slow`：
```cpp
for (size_t i = 0; i < v.size(); ++i)
    for (size_t j = 0; j < v.size(); ++j)  // j 完全没用到！
        sum += v[i] * v[i];   // bug: 多了一层循环
```

火焰图中这个函数会比预期宽 n 倍。

**修复：**
```cpp
for (double x : v) sum += x * x;   // O(n)
```

### 热点 3：热路径上的动态分配

`slow_processor.cpp:46` — `sum_with_alloc`：
```cpp
for (int i = 0; i < n; ++i) {
    std::vector<double> tmp(100, ...);   // 每次迭代都 malloc/free
    ...
}
```

火焰图中 `malloc` / `free` / `operator new` 会出现在热点中。

**修复：**
```cpp
std::vector<double> tmp(100);    // 分配一次，循环外
for (int i = 0; i < n; ++i) {
    std::fill(tmp.begin(), tmp.end(), ...);   // 复用
}
```

---

## 4.5 编译与对比测试

```bash
cd ch4_profiling
mkdir build && cd build
cmake ..
make

# 慢版本（-O0，用于火焰图采样）
./slow_processor

# 快版本（-O3，对比优化效果）
./fast_processor
```

预期输出示例：
```
=== Matrix multiply ===
slow: result=32  time=185.3 ms
fast: result=32  time=42.1 ms
speedup: 4.4x

=== Vector norm ===
slow: result=31.6  time=93.2 ms
fast: result=31.6  time=0.9 ms
speedup: 103x

=== Allocation in loop ===
slow: result=1.25e+08  time=48.7 ms
fast: result=1.25e+08  time=12.3 ms
speedup: 3.9x
```

---

## 4.6 ROS2 节点性能分析

### ros2 trace（基于 LTTng）

分析 ROS2 内部调度开销：callback 延迟、消息队列积压、执行器调度抖动。

```bash
sudo apt install ros-$ROS_DISTRO-tracetools \
                 ros-$ROS_DISTRO-tracetools-launch \
                 lttng-tools

# 启动 trace session
ros2 trace --session-name my_trace --path /tmp/my_trace

# 在另一个终端运行 ROS2 节点
ros2 run debug_ch2 talker_with_markers

# Ctrl+C 停止 trace
# 分析（需要 ros2_tracing 分析工具）
```

### topic hz / bw 监控

调试实时性问题时，先确认话题频率是否符合预期：

```bash
ros2 topic hz /debug/speed     # 应该接近 20 Hz（50ms timer）
ros2 topic hz /debug/markers   # 应该接近 2 Hz

# 如果频率偏低，检查：
# 1. 节点 CPU 占用（top / htop）
# 2. timer 回调耗时（在回调里加时间戳日志）
# 3. 消息队列是否有积压（ros2 topic bw）
```

---

## 优化原则总结

1. **先测量，再优化** — 没有 Profiler 数据不动手
2. **优化热点，而非冷路径** — 优化占 1% CPU 的函数毫无意义
3. **理解原因，再改代码** — cache miss、算法复杂度、内存分配各有不同修法
4. **改完再测量** — 验证优化效果，避免"优化"反而变慢
