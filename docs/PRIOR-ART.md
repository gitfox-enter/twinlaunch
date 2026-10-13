# 现有方案调研（Prior Art）

做这个项目之前先把轮子找一遍。结论是：**三条技术路线都已有成熟实现，但没有一个项目做"自动判断该走哪条路"这件事**。

---

## 1. 通用沙箱类

### Sandboxie-Plus

- 仓库：`sandboxie-plus/Sandboxie`（开源，另有商业增强版）
- 机制：**内核驱动级重定向**。给每个沙箱独立的文件视图与注册表视图，进程以为自己在改真实系统，实际全部落在重定向层。
- 优点：隔离最彻底；一个沙箱等于一个干净的虚拟系统；能无限多开。
- 局限：
  - 需要安装内核驱动，较重
  - 对带反作弊、带内核驱动的程序兼容性差
  - 驱动需要签名和持续维护，用户侧要装驱动才有意义
- 与本项目的关系：**不同层次**。Sandboxie 隔离的是整个运行环境，我们这个项目只解决"让它能开第二个实例"，刻意保持轻量。

---

## 2. 通道 A · 多用户会话 / 独立会话

### XueYeHuLabs/Products

- 站点：`snowwildfox.com`，下载地址 `github.com/XueYeHuLabs/Products`
- 机制：用 **Windows 本地账号 + Session 机制**开启多个独立桌面环境。宣传点是"比沙盒隔离更深，直接利用微软原生的多用户会话体系"，并强调"不是简单的进程 Hook"。
- 优点：原生级隔离；资源占用低于虚拟机；突破绝大多数软件的单例限制。
- 局限：**不是开源项目**（GitHub 仓库只放发布产物，无源码）；不考虑自动判断软件是否适用。
- 与本项目的关系：**技术路线完全一致**，是本项目通道 A 的商业化验证。差别在于我们开源、并且会自动判断某个软件是否适用这条通道。

### edgar0407/D2R-Multi-Instance

- 仓库：`edgar0407/D2R-Multi-Instance`
- 机制：PowerShell 脚本，针对《暗黑破坏神 2 重制版》。调用 `handle.exe` 关闭名为 `Check For Other Instances` 的句柄；**并且用不同的 Windows 本地用户来实现"游戏内设置各自独立"**。
- 亮点：把"关句柄"（让程序能开）和"多用户"（让数据独立）组合使用——这正是本项目通道 A 想表达的隔离思路。
- 局限：**单一软件专用**，账户名、进程名、句柄名全部硬编码。
- 与本项目的关系：证明了多用户隔离在实际生产中的可行性，同时暴露了"每个软件都要写一套"的问题。

---

## 3. 通道 B · 独立配置目录

### Zoltak-Dev/ai-multi-instance

- 仓库：`Zoltak-Dev/ai-multi-instance`
- 机制：为 Claude / Codex 桌面端每个账号分配独立 profile 目录，用 `--user-data-dir` 启动。**纯 Python 标准库，无任何第三方依赖**，另有预编译二进制。
- 极有价值的记录：项目文档明确写了 Codex 的失败案例——`bootstrap.js` 在 `requestSingleInstanceLock()` 之前调用 `app.setPath('userData', <硬编码路径>)`，导致**命令行参数永远到不了单实例检查，第二个实例必定退出**。Claude 则正常支持该参数。
- 局限：只针对 Claude / Codex 两款应用；profile 建立后仍需处理登录回调（MSIX 协议激活会落到默认实例上，只能靠快照法绕）。
- 与本项目的关系：**这是通道 B 的直接先例，也是"静态探测不够、必须实测"的最佳论据**。另外它证明了"纯标准库 Python 做这类工具"完全可行。

### suuhm/rustdesk-multi-instance

- 仓库：`suuhm/rustdesk-multi-instance`
- 机制：PowerShell + GUI。为每个实例准备独立的 `APPDATA` 目录，**启动前临时修改 `APPDATA` 环境变量**指向该实例目录，从而让程序把配置写到别处。
- 局限：单一软件专用；改环境变量的做法对本项目有参考价值（是"独立配置目录"的一个变体：不传参数，改环境）。

### neo0oen619/apollo-multi-instance-launcher

- 仓库：`neo0oen619/apollo-multi-instance-launcher`
- 机制：为 Apollo/Sunshine 每个 profile 建独立运行时目录，重写配置文件，处理端口冲突、TLS 密钥、日志隔离。Python + PySide6。
- 亮点：**处理了"多实例之间还共享其他资源"的问题**（端口族、密钥、日志），这提示本项目：换数据目录之外，可能还需要处理端口、命名管道等共享资源。
- 局限：单一软件专用，依赖 PySide6 / psutil（非零依赖）。

---

## 4. 关句柄 / 挂钩类（超出本项目范围，但列出以说明差异）

| 项目 | 目标 | 机制 |
|---|---|---|
| `Tb1281/scr-multi-launcher` | 星际争霸重制版 | 找到并关闭名为 `Starcraft Check For Other Instances` 的互斥体句柄。Rust + iced |
| `akash-devs/roblox-multi` | Roblox | 抢先持有 `ROBLOX_singletonEvent` + 文件锁防 cookie 库损坏。Python |
| `HiAlfie/dznvBlox` | Roblox | 自动关闭 `ROBLOX_singletonEvent` / `ROBLOX_singletonMutex` 句柄，支持正则匹配。Python + GUI |
| `SAM1430B/WinSplitPlus` | 通用游戏 | **EasyHook 注入**，改窗口类名/窗口名 + 杀互斥体。C++ |

**这些项目都做了我们不做的事**：注入进程、改内存、挂钩 API。这条路对聊天软件和网游有被杀软/反作弊识别的风险。本项目刻意不碰。

---

## 5. 结论：空白点在哪

| | 通用（不绑定某款软件） | 通道 A | 通道 B | 自动选通道 | 需注入/驱动 | 开源 |
|---|---|---|---|---|---|---|
| **twinlaunch** | 是 | 是 | 是 | **是** | 否 | 是 |
| Sandboxie-Plus | 是 | 否 | 否 | 否 | 是（驱动） | 是 |
| XueYeHuLabs/Products | 是 | 是 | 否 | 否 | 否 | 否 |
| edgar0407/D2R-Multi-Instance | 否 | 是 | 否 | 否 | 否 | 是 |
| Zoltak-Dev/ai-multi-instance | 否 | 否 | 是 | 否 | 否 | 是 |
| suuhm/rustdesk-multi-instance | 否 | 否 | 是 | 否 | 否 | 是 |
| neo0oen619/apollo-multi-instance-launcher | 否 | 否 | 是 | 否 | 否 | 是 |
| sc-multi-launcher / roblox-multi / dznvBlox | 否 | 否 | 否 | 否 | 部分注入 | 是 |
| WinSplitPlus | 是 | 否 | 否 | 否 | **是（注入）** | 是 |
| 商业"多开器" | 部分 | 部分 | 否 | 否 | 常需注入 | 否 |

**三点观察**

1. **所有开源实现都是"一软一策"。** 每款软件单独写一个工具，账户名、进程名、句柄名、参数名全部硬编码。没有一个是通用的。
2. **没有任何项目在拉起实例之前先判断该用哪种隔离。** 这正是本项目要填的空白。
3. **"两条通道可以并存"这件事已经被间接验证过**——D2R-Multi-Instance 同时用了关句柄和多用户，只是因为目标是同一款游戏，没有推广成通用能力。

**因此 twinlaunch 的定位不是"发明新方法"，而是"把已有方法的选型过程自动化"。** 技术风险低（每条路都有先例），价值在探测与决策层。
