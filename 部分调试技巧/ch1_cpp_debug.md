# 第一章：C++ 调试技巧

## 概述

本章以 CLion 图形化工具为主，覆盖日常 C++ 调试中最高频的场景：条件断点精准定位循环 bug、Watchpoint 追踪内存破坏、多线程面板隔离竞争问题。命令行 GDB/LLDB 作为补充。

练习文件：`ch1_cpp_debug/main.cpp`

---

## 1.1 断点基础与条件断点

### 普通断点

在 CLion 中点击行号左侧的槽（gutter）即可设置断点，程序运行到该行时暂停。调试工具栏的核心按键：

| 操作 | 快捷键 | 说明 |
|------|--------|------|
| Step Over | F8 | 执行当前行，不进入函数 |
| Step Into | F7 | 进入当前行的函数调用 |
| Step Out | Shift+F8 | 跳出当前函数 |
| Resume | F9 | 继续运行到下一个断点 |
| Evaluate | Alt+F8 | 暂停时执行任意表达式 |

### 条件断点

**使用场景**：循环体内只想在特定条件下暂停，比如 `i == 42` 或 `ptr == nullptr`。

**CLion 操作**：
1. 右键已有断点 → 弹出 Breakpoint Properties 浮窗
2. **Condition** 字段输入 C++ 布尔表达式，如 `current->val == 30`
3. 勾选 **Suspend** 决定是否暂停；取消勾选 + 填写 **Log message** 可做"只打印不暂停"的日志断点

**Log message 断点**（非常实用）：
- 不暂停程序，只在 Debug Console 打印一行日志
- 支持表达式插值：`"loop i={i}, ptr={current}"`
- 相当于不改代码临时加 `printf`，调试完直接删断点即可

---

## 1.2 Watchpoint（数据断点）

### 概念

Watchpoint 不是"在某行暂停"，而是"当某个内存地址被读或写时暂停"。是追踪内存破坏（栈溢出、越界写入、野指针）的最强工具。

**CLion 操作**：
1. 程序暂停状态下，在 Variables 或 Memory 面板找到目标变量
2. 右键变量 → **Add Watchpoint**
3. 选择触发条件：**Write**（被写入时）/ **Read**（被读取时）/ **Access**（任意访问）

> 注意：硬件 Watchpoint 数量有限（x86 通常 4 个），CLion 超出时自动降级为软件 Watchpoint（较慢）。

### 对应练习

`section2_oob_write` 在 `main.cpp:55`：
```cpp
int sentinel = 0xDEAD;   // <-- 对此变量设置 Watchpoint (Write)
int arr[5] = {1, 2, 3, 4, 5};
for (int i = 0; i <= 5; ++i) {  // bug: i <= 5 应为 i < 5
    arr[i] = i * 10;
}
```

练习步骤：
1. 在 `int sentinel = 0xDEAD` 行设置普通断点，让程序暂停
2. 在 Variables 面板右键 `sentinel` → Add Watchpoint → Write
3. 继续运行（F9），Watchpoint 会在 `arr[5] = 50` 写入 `sentinel` 的内存时自动触发
4. 查看调用栈确认是哪行写入，修复 `i <= 5` 为 `i < 5`

---

## 1.3 内存视图

**打开方式**：调试暂停时 → 菜单 View → Memory（或在 Variables 面板右键变量 → Show in Memory View）

**常用操作**：
- 十六进制视图直接观察原始字节
- 在地址栏输入 `&arr` 跳转到数组起始地址
- 可以看到 `arr[5]` 越界写入后相邻内存的变化

---

## 1.4 Evaluate Expression

调试暂停时按 **Alt+F8** 打开求值窗口：
- 执行任意 C++ 表达式：`current->next->val`
- 调用函数：`strlen(buf)`
- **修改变量值**：在 Variables 面板双击变量值直接编辑，或在 Evaluate 中 `i = 100`
- 临时修改变量验证修复方案，不用重新编译

---

## 1.5 多线程调试

### CLion Threads 面板

调试暂停时，左侧 **Frames** 面板上方有线程下拉列表（或独立的 Threads 标签页）：
- 显示所有存活线程及其当前位置
- 点击切换线程 → Frames 面板和 Variables 面板同步切换到该线程的上下文
- 可以暂停单个线程：右键线程 → Suspend

### Thread-specific Breakpoint

右键断点 → More → **Thread filter**：只对指定线程名/ID 触发，用于隔离特定线程的行为。

### 对应练习

`section3_threads` 在 `main.cpp:75`：
```cpp
void increment_worker(int thread_id, int iterations) {
    for (int i = 0; i < iterations; ++i) {
        ++shared_counter;   // <-- 设置断点，切换线程观察 shared_counter
        std::this_thread::sleep_for(std::chrono::microseconds(1));
    }
}
```

练习步骤：
1. 在 `++shared_counter` 行设置断点
2. 运行，断点触发后查看 Threads 面板，两个 worker 线程都可见
3. 切换到另一个线程，观察它的 `i` 值和 `shared_counter` 值
4. 对比 `increment_worker_safe`（加锁版本）的行为差异

---

## 1.6 调用栈与帧切换

程序崩溃或断点暂停时，**Frames** 面板显示完整调用链：

```
► increment_worker   main.cpp:79
  std::thread::...
  main              main.cpp:100
```

点击任意帧 → Variables 面板切换到该帧的局部变量。对于递归函数或深层调用非常有用。

---

## 1.7 STL 容器可视化

CLion 内置 GDB Pretty Printers 和自定义 renderers，`std::vector`、`std::map`、`std::string` 等直接展示内容，无需手动展开指针：

```
▼ v  std::vector<int> size=5
    [0] = 10
    [1] = 20
    [2] = 30
    [3] = 40
    [4] = 50
```

---

## 1.8 GDB/LLDB 控制台

调试时底部 **GDB** 标签页可直接输入命令：

```
p current->val          # 打印变量
p *arr@5               # 打印数组前5个元素
x/16xb &sentinel        # 以16进制字节查看内存
info threads            # 列出所有线程
thread 2                # 切换到线程2
bt                      # 打印调用栈
watch sentinel          # 命令行方式设置 watchpoint
```

---

## 编译与运行

```bash
cd ch1_cpp_debug
mkdir build && cd build
cmake .. && make
./debug_ch1
```

CLion 直接打开 `ch1_cpp_debug/` 目录，识别 `CMakeLists.txt` 后点击 Debug 按钮即可。
