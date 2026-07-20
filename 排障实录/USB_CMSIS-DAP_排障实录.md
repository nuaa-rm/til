# 从 Linux“收不到串口数据”到完整打通 CMSIS-DAP：一次 Godot、CDC ACM 与 HID 排障实录

> 协议更新说明（2026-07-20）：本文记录的是设备尚未启用 CRC 时的历史抓包与排障结论。当前设备的 TX/RX 帧尾均已追加 CRC-8/ATM，校验范围为“帧头 + 数据区”；请以项目根目录 `README.md` 和 `scripts/serial_protocol.gd` 为准。

> 日期：2026-07-19  
> 项目：Target Motion Console  
> 上位机：Godot 4.7.1  
> USB 设备：Horco CMSIS-DAP，VID:PID 为 `ef1a:74e5`  
> 设备接口：CMSIS-DAP HID + CDC ACM 串口  
> Windows 已知正常参数：115200 baud

## 摘要

最初的现象是：同一设备在 Windows 下以 115200 可以正常读取，但在 Linux 下，`moserial` 和 Godot 上位机看起来都收不到数据。排查过程中又陆续出现了 `/dev/ttyACM0` 变成 `/dev/ttyACM1`、Godot 提示“设备不存在”、HID 初始化脚本能够输出 `DAP firmware: 2.1.0`、内核日志出现 `error -71` 等看似不相关的信号。

最终确认，这不是一个单点故障，而是几层问题叠加：

1. 这是一台 USB 复合设备，既有 CMSIS-DAP HID 接口，也有 CDC ACM 串口接口。现场行为表明，需要先通过 HID 发送一次 `DAP_Info` 固件版本查询，设备才进入预期工作状态。该请求为 65 字节：`00 00 04` 后接 62 个 `00`。
2. USB 设备发生过多次断开和重新枚举，CDC ACM 节点会在 `/dev/ttyACM0` 与 `/dev/ttyACM1` 之间变化，不能把编号写死。
3. Godot 主程序曾使用 `FileAccess.file_exists()` 检查 `/dev/ttyACM*`。字符设备不是普通文件，这个检查会误判，导致设备明明存在却显示“设备不存在”。
4. 界面原先只统计“成功解析的协议帧”，而不是“串口收到的原始字节”。因此 `RX=0` 并不能证明串口回调没有数据。
5. 原始抓包确认接收协议为 `AF FA + 43 × float32`，完整帧长 174 字节，不包含命中 bool，也没有 RX CRC。发送方向则是 `BF FB + float32 + uint32`，共 10 字节，不带 CRC。
6. Linux 下的 `ModemManager`、115200/8N1 参数和用户权限都被逐项检查。配置 udev 规则后，它们不是最终阻塞点。
7. 内核记录过 USB `error -71` 和频繁断连。这是物理链路、Hub、线材或设备固件复位层面的独立风险，虽然不是 Godot 误判和协议解析问题的直接原因，但会造成重新编号和瞬时掉线。

最终，上位机新增了“初始化 DAP”按钮，在后台线程中调用项目内置 HID helper，成功得到：

```text
HID · DAP firmware 2.1.0
```

Godot 真实串口集成测试也成功运行 5 秒：

```text
Opened /dev/ttyACM1 at 115200 baud
Raw callbacks: 334, raw bytes: 34686, valid frames: 197, discarded bytes: 408
```

这证明最终链路已经从 HID 初始化、CDC ACM 打开、原始接收、协议解析一直打通到 Godot UI。

---

## 一、问题最初是什么样的

最初掌握的信息如下：

- Windows 下用 115200 可以正常读取。
- Linux 下能看到 `/dev/ttyACM0`，后来又变成 `/dev/ttyACM1`。
- `moserial` 看不到数据，但下位机理论上一直在发送。
- Godot 上位机连接后没有遥测，或者直接提示“设备不存在”。
- 命中字段尚未实装，因此先从串口数据结构中屏蔽，不能把命中 bool 当作故障重点。
- 设备还带有 HID/CMSIS-DAP 接口。
- 运行一个 `dap_connect.sh` 后能得到：

```text
DAP firmware: 2.1.0
```

这些现象很容易让排查陷入“是不是波特率”“是不是 Godot 插件”“是不是 HID 抢了串口”“是不是 CRC 错了”的来回猜测。更有效的方法是按层验证，每一层只回答一个问题。

---

## 二、建立分层排查模型

本次采用的排查顺序如下：

| 层级 | 要回答的问题 | 主要工具 |
|---|---|---|
| USB 物理与枚举层 | 设备有没有被内核识别？是否反复断连？ | `journalctl -k`、`lsusb`、sysfs |
| 设备节点层 | CDC ACM 和 HID 节点分别是什么？是否重新编号？ | `ls`、`find`、`udevadm` |
| 权限与占用层 | 当前用户能否读写？是否被别的进程占用？ | `id`、`getfacl`、`fuser`、`systemctl` |
| 串口参数层 | 是否真的是 115200、8N1、无流控？ | `stty` |
| 原始数据层 | 不经过应用协议，内核是否能读到字节？ | `dd`、`xxd` |
| 协议层 | 帧头、帧长、字段数量和 CRC 是否匹配？ | 十六进制抓包、帧间距计算 |
| Godot 扩展层 | 插件是否能真正打开、读取和发信号？ | Headless 集成测试、`file`、`ldd`、内核日志 |
| Godot 应用层 | UI 显示的是原始字节还是有效帧？设备存在性检查是否可靠？ | 代码审查、诊断计数器 |
| HID 初始化层 | DAP 脚本实际发送什么？是否确实有响应？ | Python、hidraw、`strace` |

核心原则是：先证明“有没有原始字节”，再讨论协议；先证明“系统能否打开设备”，再讨论 UI。

---

## 三、第一步：确认 USB 设备到底枚举成了什么

### 3.1 查看内核识别结果

使用命令：

```bash
journalctl -k --no-pager | rg 'Horco|ttyACM|hidraw|error -71|USB disconnect'
```

关键输出：

```text
usb 1-2.2: Product: Horco CMSIS-DAP
usb 1-2.2: Manufacturer: Horco
hid-generic ... hiddev2,hidraw4: USB HID v1.10 Device [Horco Horco CMSIS-DAP]
cdc_acm 1-2.2:1.1: ttyACM0: USB ACM device
```

这说明它不是单纯的 USB 转串口，而是一台复合设备：

- HID 接口：`hidraw4`，用于 CMSIS-DAP 命令；
- CDC ACM 接口：`ttyACM0` 或 `ttyACM1`，用于串口数据。

### 3.2 发现 ACM 编号会变化

后续日志中出现：

```text
cdc_acm 1-2.1:1.1: ttyACM0: USB ACM device
...
usb 1-2.1: USB disconnect
...
cdc_acm 1-2.1:1.1: ttyACM1: USB ACM device
```

所以 `/dev/ttyACM0` 变成 `/dev/ttyACM1` 并不是应用修改导致的，而是 USB 重新枚举后的内核编号变化。

最终建议优先使用稳定链接：

```text
/dev/serial/by-id/usb-Horco_Horco_CMSIS-DAP_2744335732-if01
```

而不是永久写死 `/dev/ttyACM0` 或 `/dev/ttyACM1`。

### 3.3 `error -71` 的意义

日志还出现过：

```text
device descriptor read/64, error -71
device not accepting address 21, error -71
usb 1-2.2: USB disconnect
```

`error -71` 对应 USB 协议层异常，常见方向包括：

- USB 线材或接头质量；
- Hub 或扩展坞；
- 供电不稳定；
- 设备固件主动复位；
- USB 端口兼容性。

它解释了为什么设备会反复消失、重新出现并换编号，但不能单独解释 Godot 的“设备不存在”误报，也不能代替协议抓包。

---

## 四、一个容易踩的坑：沙箱里看不到宿主机 `/dev`

最初在受限诊断环境中执行：

```bash
ls -l /dev/ttyACM1
```

返回：

```text
ls: 无法访问 '/dev/ttyACM1': 没有那个文件或目录
```

但同时：

```bash
find /sys/class/tty -maxdepth 1 -name 'ttyACM*' -printf '%f -> %l\n'
```

却能看到：

```text
ttyACM1 -> ../../devices/pci0000:00/.../tty/ttyACM1
```

这说明内核 sysfs 中设备存在，只是诊断进程所在的 `/dev` 命名空间没有映射该节点。

切换到宿主机环境后再执行：

```bash
ls -l /dev/ttyACM1
```

真实输出为：

```text
crw-rw---- 1 root dialout 166, 1 Jul 19 20:30 /dev/ttyACM1
```

经验：如果 `/sys/class/tty` 有设备、内核日志也显示枚举成功，而 `/dev` 中没有，需要先确认自己是否在容器、沙箱或隔离命名空间中，不能立刻判断宿主机设备消失。

---

## 五、确认设备身份、权限和 ModemManager

### 5.1 `udevadm`：确认这就是目标设备

命令：

```bash
udevadm info --query=property --name=/dev/ttyACM1
```

关键输出：

```text
ID_VENDOR_ID=ef1a
ID_MODEL_ID=74e5
ID_VENDOR=Horco
ID_MODEL=Horco_CMSIS-DAP
ID_SERIAL_SHORT=2744335732
ID_USB_INTERFACE_NUM=01
ID_USB_DRIVER=cdc_acm
ID_USB_INTERFACES=:030000:020201:0a0000:
ID_MM_DEVICE_IGNORE=1
```

作用：

- 确认 VID/PID；
- 确认当前节点属于 Horco CMSIS-DAP；
- 确认接口驱动为 `cdc_acm`；
- 确认设备同时包含 HID、CDC 通信等接口；
- 确认 udev 已设置 `ID_MM_DEVICE_IGNORE=1`，要求 ModemManager 忽略它。

### 5.2 检查当前用户组

命令：

```bash
id
```

宿主机输出中包含：

```text
uid=1000(mijiao) gid=1000(mijiao) ... 20(dialout) ... 46(plugdev) 107(input) ...
```

这三个组分别对应：

- `dialout`：CDC ACM 串口；
- `input`：hidraw；
- `plugdev`：复合 USB 设备或 libusb 工具。

### 5.3 检查 ACL

命令：

```bash
getfacl -p /dev/ttyACM1
```

输出：

```text
# owner: root
# group: dialout
user::rw-
group::rw-
other::---
```

当前用户属于 `dialout`，因此能够读写串口。

HID 稳定链接的权限为：

```bash
ls -l /dev/cmsis-dap-hid
getfacl -p /dev/cmsis-dap-hid
```

输出：

```text
lrwxrwxrwx 1 root root 7 ... /dev/cmsis-dap-hid -> hidraw4
# owner: root
# group: input
user::rw-
group::rw-
other::r--
```

当前用户属于 `input`，所以 HID 也有读写权限。

### 5.4 检查设备是否被占用

命令：

```bash
fuser -v /dev/ttyACM1
```

没有输出，说明当时没有进程占用设备。

### 5.5 检查 ModemManager

命令：

```bash
systemctl --no-pager --full status ModemManager.service
```

输出显示服务确实在运行：

```text
Active: active (running)
Main PID: 4165 (ModemManager)
```

但日志中同时显示该设备不被支持，udev 属性也有：

```text
ID_MM_DEVICE_IGNORE=1
```

并且 `fuser` 没有发现占用，因此 ModemManager 不是最终原因。

---

## 六、确认串口参数：115200、8N1、无流控

命令：

```bash
stty -F /dev/ttyACM1 -a
```

关键输出：

```text
speed 115200 baud
-parenb -parodd cs8 -cstopb
cread clocal -crtscts
-ixon -ixoff
-icanon -echo
```

解释：

- `speed 115200 baud`：波特率正确；
- `cs8`：8 数据位；
- `-parenb`：无奇偶校验；
- `-cstopb`：1 停止位；
- `-crtscts`：无硬件流控；
- `-ixon -ixoff`：无软件流控；
- `-icanon -echo`：原始字节模式，不做终端行处理。

因此串口参数与 Windows 已验证配置一致，115200/8N1 不是最终故障点。

项目使用的 Linux 串口扩展还增加了：

- `ttyACM`、`ttyUSB` 枚举；
- DTR/RTS 拉起；
- 230400、460800、921600、4000000 波特率映射；
- 不支持的波特率明确失败，不再静默回退到 9600。

对应补丁位于：

```text
patches/godot-serial-extension-linux.patch
```

---

## 七、不要先相信 UI：直接读取原始字节

### 7.1 最小打开测试

命令：

```bash
timeout 2s dd if=/dev/ttyACM1 bs=1 count=1 status=none >/dev/null
echo $?
```

输出：

```text
0
```

这说明当前用户能够打开设备，并且在 2 秒内实际读到了至少 1 个字节。

### 7.2 设置串口并抓取十六进制

命令：

```bash
stty -F /dev/ttyACM1 raw 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts clocal
timeout 8s xxd -g 1 -l 1024 /dev/ttyACM1
```

抓包节选：

```text
00000000: af fa b8 d8 08 3e 00 00 00 00 00 00 00 00 00 00
00000010: 00 00 00 00 00 00 00 00 00 00 c3 39 1c 3e 40 63
...
000000a0: fc 40 5c 3f 17 41 00 00 00 00 00 00 00 00 af fa
...
00000150: 5c 3f 17 41 00 00 00 00 00 00 00 00 af fa b8 d8
...
```

帧头出现的位置为：

```text
0x000
0x0AE
0x15C
0x20A
...
```

相邻帧头间距：

```text
0xAE = 174 bytes
```

而：

```text
2 字节帧头 + 43 × 4 字节 float32 = 174 字节
```

由此直接得到接收协议：

- 帧头：`AF FA`；
- 数据区：43 个 little-endian `float32`，共 172 字节；
- 完整帧：174 字节；
- 不包含命中 bool；
- 不包含 RX CRC。

这是整个排查中最关键的证据。它同时证明：

1. Linux 确实收到了数据；
2. 波特率正确，否则很难得到稳定的固定帧头和固定帧距；
3. 问题已经可以从“USB/串口层”缩小到“应用预检查、协议解析或 UI 诊断层”。

---

## 八、为什么 UI 的 `RX=0` 不能说明串口没数据

原应用逻辑只在协议解析器返回完整合法帧后才更新：

- RX 帧计数；
- 最后收包时间；
- 原始帧显示；
- UI 遥测字段。

因此如果发生以下任意一种情况：

- 帧头不匹配；
- 帧长不匹配；
- CRC 假设错误；
- 串口回调只有半帧；
- 打开端口时从帧中间开始读取；

界面都会显示为 `RX=0`，看起来像完全没数据。

修复方式是把两个指标分开：

```text
原始接收字节数 / 最近原始回调
有效协议帧数 / 最近有效帧
```

现在 `_on_serial_data()` 一进入就会记录：

- 原始回调字节数；
- 原始累计字节数；
- 最近一段十六进制；
- 原始数据最后到达时间。

之后才把数据送入协议解析器。这样可以立刻判断：

```text
RAW 增长但 FRAME 不增长 -> 协议层问题
RAW 完全不增长          -> 串口、扩展、权限、占用或设备状态问题
```

---

## 九、协议方向必须分开：RX 与 TX 不是同一个帧头

抓包和后续协议确认得到最终定义。

### 上位机接收 RX

```text
AF FA + 43 × float32
```

总长度：

```text
2 + 172 = 174 bytes
```

没有 bool，没有 CRC。

### 上位机发送 TX

```text
BF FB + target_rpm(float32) + translation_power(uint32)
```

总长度：

```text
2 + 4 + 4 = 10 bytes
```

没有 CRC。

这里非常容易混淆：接收帧头是 `AF FA`，发送帧头是 `BF FB`。调试时必须明确当前讨论的是哪个方向。

此外，旧测试中曾残留 `BF FB` 作为 RX 拆包测试帧头，导致实现已经修正但测试仍失败。测试也必须跟协议一起更新，不能把过期测试失败误判为串口故障。

---

## 十、验证 Godot 串口扩展，而不是只相信命令行

系统命令能读到数据后，还需要证明 Godot 的扩展能完成同样的事。

为此运行了一个 5 秒的临时 Headless 集成测试，逻辑为：

1. 实例化 `SerialPort`；
2. 打开 `/dev/ttyACM1`，115200；
3. 同时观察 `data_received` 和可用字节轮询；
4. 把所有数据送入真实协议解析器；
5. 输出原始字节数和有效帧数。

输出：

```text
Godot Engine v4.7.1.stable.official
Opened /dev/ttyACM1 at 115200 baud
Raw callbacks: 334, raw bytes: 34686, valid frames: 197, discarded bytes: 408
```

验证关系：

```text
197 × 174 + 408 = 34686
```

这说明读取到的所有字节都能由“有效帧 + 初始或重同步丢弃字节”解释，Godot 串口扩展和协议解析器已经形成闭环。

### 扩展崩溃旁支

内核曾记录：

```text
Godot_v4.7.1 ... invalid opcode ... in libserial.so
```

因此还检查过：

```bash
file bin/libserial.so
ldd bin/libserial.so
strings -a bin/libserial.so | rg 'SerialPort|data_received|read_bytes|get_available_bytes'
```

代表性输出：

```text
ELF 64-bit LSB shared object, x86-64
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6
SerialPort
data_received
read_bytes
get_available_bytes
```

当前重新构建并打补丁后的扩展已经通过真实 5 秒读取测试，因此历史崩溃不是最终仍然存在的阻塞点。

---

## 十一、Godot 为什么提示“设备不存在”

主程序曾在调用串口扩展前做以下检查：

```gdscript
if port.begins_with("/dev/") and not FileAccess.file_exists(port):
    _set_connection_state("设备不存在", ...)
    return
```

问题是 `/dev/ttyACM1` 是字符设备，不是普通文件。Godot 的 `FileAccess.file_exists()` 对它的判断并不可靠，于是出现：

```text
系统 ls 能看到设备
串口扩展也能打开设备
但 UI 预检查提前返回“设备不存在”
```

修复方式不是继续增加更多普通文件检查，而是删除这层预检查，直接以真正的串口打开结果为准：

```gdscript
var opened := bool(_serial.call("open", port, baud))
```

串口驱动的 `open()` 才是判断字符设备是否可用的权威操作。

同时，扫描 `/dev/serial/by-id` 前增加目录存在性检查，避免在容器或精简系统中因为目录不存在而打印无关错误。

---

## 十二、回到 HID：原初始化脚本实际做了什么

找到的原脚本位置：

```text
/home/mijiao/下载/dap_connect.sh
```

核心内容：

```python
fd = os.open('/dev/cmsis-dap-hid', os.O_RDWR)
os.write(fd, b'\x00\x00\x04' + b'\x00' * 62)
time.sleep(0.05)
r = os.read(fd, 64)
ver = r[2:2 + r[1]].decode()
print(f'DAP firmware: {ver}')
```

它发送的是 CMSIS-DAP `DAP_Info` 请求，信息 ID 为 `0x04`，用于查询固件版本。

从 HID report 角度看：

| 字节 | 值 | 含义 |
|---:|---:|---|
| 0 | `00` | HID Report ID |
| 1 | `00` | CMSIS-DAP `DAP_Info` 命令 |
| 2 | `04` | Firmware Version 信息 ID |
| 3～64 | `00` | 补齐 report |

完整请求长度为 65 字节。

运行脚本：

```bash
timeout 3s /home/mijiao/下载/dap_connect.sh
```

输出：

```text
DAP firmware: 2.1.0
```

严格来说，这是一条版本查询，而不是 CDC ACM 串口配置命令。但现场现象表明，在这台设备上执行该 HID 交互后，设备进入了预期的数据工作状态，因此它被作为“DAP 初始化/唤醒”步骤整合进上位机。

### 没有发现开机服务调用它

使用：

```bash
rg -n -i 'dap_connect\.sh|cmsis-dap|ef1a.*74e5' \
  /etc/systemd/system \
  /usr/lib/systemd/system \
  /lib/systemd/system \
  /etc/xdg/autostart \
  ~/.config/autostart \
  ~/.config/systemd
```

没有匹配输出，因此当时并没有 systemd 或桌面自启动项自动执行该脚本，它是手动运行的。

---

## 十三、配置 udev：稳定 HID 路径、权限和 ModemManager 忽略

最终规则位于：

```text
/etc/udev/rules.d/99-cmsis-dap.rules
```

内容：

```udev
# Horco CMSIS-DAP (ef1a:74e5)
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="ef1a", ATTR{idProduct}=="74e5", MODE="0660", GROUP="plugdev", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"

ACTION=="add|change", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="ef1a", ATTRS{idProduct}=="74e5", MODE="0660", GROUP="input", TAG+="uaccess", SYMLINK+="cmsis-dap-hid"

ACTION=="add|change", SUBSYSTEM=="tty", ATTRS{idVendor}=="ef1a", ATTRS{idProduct}=="74e5", MODE="0660", GROUP="dialout", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"
```

作用分别是：

1. 给整个 USB 复合设备设置 `plugdev` 权限；
2. 为 HID 创建稳定链接 `/dev/cmsis-dap-hid`；
3. 为 CDC ACM 串口设置 `dialout` 权限；
4. 要求 ModemManager 忽略该设备。

应用规则的一般命令：

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

必要时重新插拔设备，使所有接口重新匹配规则。

---

## 十四、Godot 原生 `FileAccess` 打不开 hidraw：到底是不是权限

最初尝试直接在 GDScript 中：

```gdscript
var device := FileAccess.open("/dev/cmsis-dap-hid", FileAccess.READ_WRITE)
```

Godot 返回：

```text
open failed: Can't open file
```

这时不能直接说“Godot 不支持”，也不能直接说“权限不足”，必须查看内核实际返回值。

### 14.1 权限侧证据

- 当前用户属于 `input`；
- `/dev/hidraw4` 的组是 `input`，组权限为 `rw-`；
- 同一用户运行 Python 可以正常打开并得到 `DAP firmware: 2.1.0`。

### 14.2 使用 `strace` 查看 Godot 是否真的调用了 `open`

命令：

```bash
strace -f -e trace=openat,open,access,faccessat2 \
  godot --headless --path . --script /tmp/test_godot_hid_open.gd
```

Godot 输出：

```text
/dev/cmsis-dap-hid -> Can't open file, opened=false
/dev/hidraw4 -> Can't open file, opened=false
```

关键观察是：`strace` 中没有出现以下系统调用：

```text
openat(..., "/dev/cmsis-dap-hid", ...)
openat(..., "/dev/hidraw4", ...)
```

也就是说，Godot 在进入内核 `open/openat` 之前就拒绝了这类路径，并没有收到 `EACCES`。

结论：这次失败不是权限问题，而是 `FileAccess` 不适合作为 hidraw 字符设备访问接口。

---

## 十五、最终实现：把 DAP 初始化真正整合进上位机

由于 GDScript 原生文件 API 无法直接打开 hidraw，最终采用：

```text
Godot 初始化按钮
    -> 后台 Thread
    -> /usr/bin/python3
    -> 项目内置 scripts/dap_init.py
    -> /dev/cmsis-dap-hid
    -> 发送 65 字节 DAP_Info 请求
    -> 等待最多 1 秒
    -> 读取 64 字节响应
    -> 返回固件版本到 UI
```

项目 helper 不再依赖下载目录中的旧脚本。它实现了：

- 非阻塞打开 hidraw；
- 处理部分写入；
- 写超时；
- 读超时；
- 响应命令检查；
- 固件版本长度检查；
- 简洁错误信息。

按钮运行期间会禁用，避免重复点击；成功后显示：

```text
HID · DAP firmware 2.1.0
```

真实自动点击测试输出：

```text
Godot Engine v4.7.1.stable.official
DAP button status: HID · DAP firmware 2.1.0
```

HID 操作在后台线程中执行，因此设备响应变慢时不会冻结 UI。

---

## 十六、最终链路

```mermaid
flowchart LR
    A[点击 初始化 DAP] --> B[Godot 后台线程]
    B --> C[scripts/dap_init.py]
    C --> D[/dev/cmsis-dap-hid]
    D --> E[DAP_Info 00 00 04]
    E --> F[DAP firmware 2.1.0]

    G[点击 连接设备] --> H[SerialPort.open]
    H --> I[/dev/serial/by-id 或 ttyACM]
    I --> J[原始字节计数与 HEX]
    J --> K[AF FA / 174-byte 解析器]
    K --> L[遥测 UI]
```

推荐操作顺序：

1. 插入设备；
2. 点击“初始化 DAP”；
3. 确认显示固件版本；
4. 选择 `/dev/serial/by-id/...`；
5. 选择 115200；
6. 点击“连接设备”；
7. 先观察 RAW 字节是否增长，再观察有效帧计数。

---

## 十七、最终根因与排除项

| 项目 | 结论 | 证据 |
|---|---|---|
| 设备需要 HID 交互 | 现场确认需要作为初始化/唤醒步骤 | 原脚本与新按钮均返回固件版本，执行后 CDC 链路进入可用状态 |
| `/dev/ttyACM*` 编号固定 | 错误假设 | 内核日志明确出现 ACM0/ACM1 切换 |
| Godot “设备不存在” | 应用误判 | 删除 `FileAccess.file_exists()` 后扩展可正常打开 |
| Linux 串口完全没数据 | 错误判断 | `dd` 成功，`xxd` 抓到稳定 174 字节帧 |
| 115200/8N1 错误 | 排除 | `stty` 与 Windows 已验证配置一致 |
| 用户无串口权限 | 排除 | 用户属于 `dialout`，实际打开和读取成功 |
| 用户无 HID 权限 | 排除 | 用户属于 `input`，Python 打开成功 |
| ModemManager 抢占 | 排除 | `fuser` 无占用，udev 设置 `ID_MM_DEVICE_IGNORE=1` |
| HID 和 CDC 不能共存 | 排除 | 两个接口同时枚举，HID 初始化后 CDC 正常收包 |
| RX 携带 bool | 排除 | 帧距严格为 174，正好等于 2 + 43×4 |
| RX 携带 CRC | 排除 | 原始帧长度没有额外 CRC 字节 |
| USB 链路完全稳定 | 尚不能确认 | 日志仍有断连和 `error -71`，需继续关注物理层或固件复位 |

因此，实际问题可以概括为：

> 一台需要 HID 侧交互的 CMSIS-DAP 复合设备，在 Linux 上发生过重新枚举；上位机又错误地用普通文件 API 判断字符设备是否存在，并且只显示有效协议帧而不显示原始字节。这些因素叠加后，表现成了“设备存在但程序说不存在”“串口似乎完全没数据”。

---

## 十八、可复用的排障命令清单

### 1. 枚举与内核日志

```bash
journalctl -k --no-pager | rg 'ttyACM|cdc_acm|hidraw|CMSIS-DAP|error -71|USB disconnect'
find /sys/class/tty -maxdepth 1 -name 'ttyACM*' -printf '%f -> %l\n'
```

### 2. 设备身份

```bash
udevadm info --query=property --name=/dev/ttyACM1
```

### 3. 权限

```bash
ls -l /dev/ttyACM1 /dev/hidraw4 /dev/cmsis-dap-hid
id
getfacl -p /dev/ttyACM1
getfacl -p /dev/cmsis-dap-hid
```

### 4. 占用

```bash
fuser -v /dev/ttyACM1
lsof /dev/ttyACM1
```

### 5. 串口参数

```bash
stty -F /dev/ttyACM1 -a
stty -F /dev/ttyACM1 raw 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts clocal
```

### 6. 原始读取

```bash
timeout 2s dd if=/dev/ttyACM1 bs=1 count=1 status=none >/dev/null
timeout 8s xxd -g 1 -l 1024 /dev/ttyACM1
```

### 7. ModemManager

```bash
systemctl --no-pager --full status ModemManager.service
```

### 8. HID 初始化

```bash
python3 scripts/dap_init.py /dev/cmsis-dap-hid
```

期望输出：

```text
2.1.0
```

### 9. Godot 测试

```bash
godot --headless --path . --script tests/test_protocol.gd
```

期望输出：

```text
SerialPort extension available: true
Serial protocol tests passed
```

### 10. 确认 Godot 是否真的调用了设备 `open`

```bash
strace -f -e trace=openat,open,access,faccessat2 godot ...
```

这一步特别适合区分：

- `EACCES`：权限问题；
- `ENOENT`：路径或设备节点问题；
- 根本没有 `open/openat`：应用或引擎在系统调用前就拒绝了请求。

---

## 十九、这次排查最值得保留的经验

### 1. “没有有效帧”不等于“没有串口数据”

任何二进制协议 UI 都应该同时显示原始字节计数和有效帧计数。

### 2. `/dev` 设备不是普通文件

不要用普通文件存在性 API 替代真正的设备 `open()`。

### 3. 复合 USB 设备要按接口分别看

HID、CDC ACM、libusb 接口可以属于同一物理设备，各自有不同节点、权限和用途。

### 4. 设备编号不稳定，设备身份才稳定

优先使用 `/dev/serial/by-id` 和自定义 udev symlink，而不是写死 `ttyACM0`。

### 5. 抓原始十六进制比猜协议快

稳定帧头和帧间距可以直接回答帧长、CRC、bool 和端序问题。

### 6. 权限问题要看 errno，不要只看上层错误文本

“Can't open file”并不自动等于 `EACCES`。使用 `strace` 才能看到应用是否真正调用了内核。

### 7. `error -71` 应单独作为物理层风险处理

即使应用和协议已经打通，频繁 USB 断连仍需继续检查线材、Hub、供电和设备固件。

---

## 二十、当前项目中的对应实现

| 功能 | 文件 |
|---|---|
| Godot 串口连接、RAW 诊断、DAP 按钮和线程 | `scripts/main.gd` |
| HID 初始化 helper | `scripts/dap_init.py` |
| RX/TX 协议定义与解析 | `scripts/serial_protocol.gd` |
| UI 按钮和状态标签 | `main.tscn` |
| 串口扩展 Linux 补丁 | `patches/godot-serial-extension-linux.patch` |
| 协议测试 | `tests/test_protocol.gd` |
| udev 规则 | `/etc/udev/rules.d/99-cmsis-dap.rules` |

最终验证结果：

```text
DAP button status: HID · DAP firmware 2.1.0
Serial protocol tests passed
Godot project load: exit 0
```

至此，USB 复合设备初始化、CDC ACM 串口接收、协议解析和上位机显示链路全部完成验证。
