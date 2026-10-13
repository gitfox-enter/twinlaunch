# 现有方案调研（Prior Art）

做这个项目之前先把轮子找一遍。结论是：**四条技术路线都已有成熟实现，但没有一个项目做"自动判断该走哪条路"这件事**。

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

## 5. 会话级方案 · RDP Wrapper（多用户同时登录）

来源：知乎问题 550109743 的回答（2023-08-24）中列出的"思路 3 · 折腾多用户同时登录，推荐软件 RDPWrap"。回答本身只有一句话，此处补全调研。

### 机制

Windows 客户端版（Home / Pro / Pro for Workstations）出厂就**带了**远程桌面服务，但按许可策略限制为**同时只有一个活动会话**——第二个用户登入会把第一个踢掉。

RDP Wrapper 的做法是在系统服务与 `termsrv.dll` 之间插一层，把"检查会话数上限"的那段逻辑改成直接返回通过，从而解锁代码里本就存在、只是被许可策略关掉的多会话能力。

- 关键文件：`rdpwrap.ini` —— 里面是**按 `termsrv.dll` 文件版本号索引的硬编码内存偏移**，不是通用补丁。
- 原项目 `stascorp/rdpwrap` 停在 v1.6.2，早已停更，自带 ini 追不上新 build。
- 实际可用性依赖社区维护的 ini：`sebaxakerhtc/rdpwrap.ini`（1600+ 提交，仍在更新）。装完后用 `RDPConf.exe` 自检，要求三项全绿（Wrapper installed / running / Listener state: listening）。

### 局限

| 问题 | 说明 |
|---|---|
| **每次补丁日可能失效** | Windows 更新会替换 `termsrv.dll`，偏移对不上即失效，需整段替换 ini 并重启 `TermService`。必须等社区补上你那个精确 build。 |
| **许可问题** | 客户端版开多会话属于绕过许可策略，多会话本是 Server 特性 / Windows 11 Enterprise Multi-Session（仅 Azure Virtual Desktop）能力。 |
| **杀软误报** | 因为改的是系统服务的加载方式，常被标记为 `HackTool` / `RemoteAdmin`。 |
| **搜索生态脏** | 大量二次打包的"2026 更新版"安装器带广告甚至木马，只能从原始项目 release 取。 |
| **暴露面** | 放开多会话后若把 3389 直接暴露，等于给爆破字典开门。 |

### 与本项目的关系：**相邻能力，不是第三条通道**

这是最容易误判的地方。RDP Wrapper 解决的是"**多个会话能否同时在线**"，不是"**同一个桌面上能不能并排两个窗口**"。

- 它给出的东西：第二个账户拥有一个**真正在线的独立桌面**，通过 RDP 客户端窗口呈现。
- 本项目通道 A 给出的东西：第二个实例作为**同一会话内的另一个安全上下文**启动，窗口和第一个实例**并排落在同一张桌面上**，不需要任何远程桌面客户端。

所以对"桌面上两个图标、双击各开一个"这个原始目标，**通道 A 比 RDP Wrapper 更直接**；RDP Wrapper 反而多引入了一层远程桌面。

它的真实价值在别处：**让第二个账户的会话长期在线**。通道 A 里那个第二账户平时是"离线"的，每次都要临时拉起；如果某个软件要求完整交互式会话才能正常工作，或者需要远距离操作第二账户的桌面，RDP Wrapper 才有意义。

结论：**不并入两条通道，作为"会话增强"单独记录**，优先级低于 M0–M2。

### 本机实测（2026-10-13）

| 项 | 值 |
|---|---|
| 系统 | Windows 11 25H2 · build 26200.9457 · Pro for Workstations |
| `termsrv.dll` | `10.0.26100.8875` |
| `TermService` / `UmRdpService` | 均在运行（Manual / Automatic） |
| `fDenyTSConnections` | `0` —— **远程桌面已开启** |
| `fSingleSessionPerUser` | `1` |
| RDP Wrapper | 未安装 |
| 社区 ini（sha `3dce6ffe6c53`） | 711 个 build 段；`10.0.26100` 家族 104 条；**不含 `10.0.26100.8875`**，最近邻为 `.8772` / `.8968` |

即：**当前这个 build 没被社区 ini 覆盖**，直接装会显示 `[not supported]`，需要等社区补偏移，或用邻近版本的偏移试（有风险，可能蓝屏）。

### 不适用场景

- 目标软件把单实例锁做成 `Global\` 命名空间时，多会话同样不生效（与通道 A 同病）。
- 想在同一账户下开两个实例：多会话会让两个会话**共用同一个 `%APPDATA%`**，配置互相覆盖，等于没有隔离。

---

## 6. 结论：空白点在哪

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
| RDP Wrapper（会话级） | 是 | 部分（会话隔离） | 否 | 否 | 是（改服务加载） | 是 |

> RDP Wrapper 一行标"部分"：它确实用多用户会话做隔离，但产出的是**独立桌面**而非同桌面双窗口，与原目标方向不同，详见第 5 节。

**三点观察**

1. **所有开源实现都是"一软一策"。** 每款软件单独写一个工具，账户名、进程名、句柄名、参数名全部硬编码。没有一个是通用的。
2. **没有任何项目在拉起实例之前先判断该用哪种隔离。** 这正是本项目要填的空白。
3. **"两条通道可以并存"这件事已经被间接验证过**——D2R-Multi-Instance 同时用了关句柄和多用户，只是因为目标是同一款游戏，没有推广成通用能力。

**因此 twinlaunch 的定位不是"发明新方法"，而是"把已有方法的选型过程自动化"。** 技术风险低（每条路都有先例），价值在探测与决策层。
