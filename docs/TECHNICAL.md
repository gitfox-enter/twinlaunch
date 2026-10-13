# twinlaunch 技术文档

本文档描述 twinlaunch 的架构、探测判据、数据模型与执行细节。目标是让任何人读完都能理解**为什么这样判定**，以及**判错了会怎样**。

---

## 1. 目标与非目标

**目标**

1. 对任意 Windows 桌面软件，在**不注入、不挂钩、不装驱动**的前提下实现双开。
2. 在动手之前，先给出"这个软件适合哪种方式"的结论和依据。
3. 结论可解释、可复核——每一个判定都要带上证据。

**非目标**

- 不绕过反作弊、不修改目标程序、不读取目标程序内存。
- 不提供提权能力。需要管理员权限才能运行的软件，直接判为不适用。
- 不做驱动级隔离（那是 Sandboxie 的领域，本项目明确不碰）。

---

## 2. 分层架构

```
┌──────────────────────────────────────────────┐
│  界面层 (UI)                                  │
│  软件列表 · 自检报告 · 图标管理                 │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│  决策层 (Decide)                              │
│  AppProfile → 通道建议 + 置信度 + 理由         │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│  探测层 (Probe)  —— 全程只读                   │
│  内核探测 · 安装探测 · 单实例探测 · 注册表探测   │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│  执行层 (Launch)                              │
│  通道A: CreateProcessWithLogonW + DPAPI       │
│  通道B: CreateProcess + profile 参数          │
│  图标: IShellLink                             │
└──────────────────────────────────────────────┘
```

关键约束：**探测层零写入**。它只读文件系统元数据、ACL、进程句柄表、注册表。所有产生副作用的动作（建目录、建图标、启动进程）都在执行层，且必须由用户显式触发。

---

## 3. 探测规格

### 3.1 内核探测

**目的**：判断目标是不是 Electron / Chromium 系——这决定通道 B 是否为候选。

**搜索范围**：exe 所在目录，以及其下最多 3 层子目录；优先进入这些命名模式的目录：`versions\*`、`Application\*`、`app-*`、`current`、纯版本号形式（`^\d+\.\d+`）。

> **为什么必须递归**：QQ 的安装布局是"壳 exe + 版本化负载"。`C:\Program Files\Tencent\QQNT\` 顶层只有 `QQ.exe`、`QQEX.exe` 和一堆 `api-ms-win-*` 转发 DLL，真正的 Electron 运行时在 `versions\9.9.33-52230\` 下。只看同级目录会误判为原生程序。

> **`api-ms-win-*` 不是原生的证据**：这些只是 CRT 转发 stub，Electron 应用也常见。

**特征文件与权重**

| 特征 | 权重 | 说明 |
|---|---|---|
| `icudtl.dat` | 3 | ICU 数据，Chromium 系标志 |
| `*.pak`（`chrome_100_percent.pak` / `chrome_200_percent.pak` / `resources.pak`） | 3 | Chromium 资源包 |
| `resources\app.asar` 或 `resources\app\package.json` | 3 | Electron 应用包 |
| `libEGL.dll` / `libGLESv2.dll` | 2 | Chromium 图形栈 |
| `v8_context_snapshot.bin` / `snapshot_blob.bin` | 2 | V8 快照 |
| `ffmpeg.dll` | 1 | 常见但不独有 |

**判定阈值**：总分 ≥ 6 → `high`；3–5 → `medium`；< 3 → `native`。

**输出必须带证据路径**，形如 `versions\9.9.33-52230\icudtl.dat`，而不是只说"检测到 Electron"。

**已知反例**：Electron 应用可以在启动早期调用 `app.setPath('userData', <硬编码路径>)` 再 `requestSingleInstanceLock()`，此时 `--user-data-dir` **永远到不了单实例检查**，第二个实例仍然秒退。静态探测无法识别这种情况——**这是通道 B 必须做动态实测的根本原因**。

### 3.2 安装位置与访问权限探测

**目的**：判断通道 A 是否可行（第二账户能否访问到 exe）。

**第一步：作用域判定**

路径前缀命中下列之一 → `machine` 作用域，通常可直接用：

- `%ProgramFiles%`、`%ProgramFiles(x86)%`
- `%ProgramData%`
- `%SystemRoot%`

否则 → `user` 作用域，需要进入第二步。

**第二步：ACL 判定**

读取 exe 所在目录的有效权限，检查 `BUILTIN\Users`（SID `S-1-5-32-545`）是否具备读+执行（`FILE_GENERIC_READ | FILE_GENERIC_EXECUTE`）。

- 目录自身可能没有显式 ACE，而是继承自父级 → 必须评估**有效权限**，不能只看显式条目。
- 结果为有 → `yellow`（能跑，但需留意路径与凭据陷阱）
- 结果为无 → `red`（通道 A 不可用）

**路径链检查**：目标账户对路径上每一级目录都需要"遍历"权限。Windows 默认给 `BUILTIN\Users` 授予 `SeChangeNotifyPrivilege`（绕过遍历检查），所以实践中一般不会断链，但如果某个中间目录设了显式拒绝，就会失败。

**路径展开**：如果输入来自快捷方式，其目标可能是 `%USERPROFILE%\...` 这种环境变量形式，**必须先展开**再使用。（实践踩过的坑：未展开会导致以第二账户身份去找 `C:\Users\<第二账户>\AppData\...`，文件不存在，进程秒退。）

### 3.3 单实例机制探测

**目的**：判断锁是会话级（`Local\`）还是全局级（`Global\`）——这决定通道 A 是否有效。

**流程**

1. 确认目标软件当前是否在运行。
2. 若在运行，枚举其进程的句柄：
   - `NtQuerySystemInformation(SystemExtendedHandleInformation)` 取全系统句柄表
   - 按 `UniqueProcessId` 过滤出目标进程的句柄
   - 对每个句柄 `DuplicateHandle` 到本进程
   - `NtQueryObject(ObjectTypeInformation)` 取类型名，只保留 `Mutant`（互斥体）/ `Event`（事件）/ `Semaphore`（信号量）
   - 对这些句柄再查 `NtQueryObject(ObjectNameInformation)` 取对象名
3. 判定命名空间前缀：
   - `Local\` → 会话级 → 通道 A 有效
   - `Global\` → 跨会话 → 通道 A **无效**（此时只剩杀句柄一条路，超出本项目范围）
   - 无名 → 无命名锁，或依赖窗口类名查找等其他机制

**两个必须处理的实现陷阱**

1. **`NtQueryObject(ObjectNameInformation)` 会阻塞。** 对某些对象类型（尤其 `File`、管道）该调用可能永久不返回。必须只对 `Mutant`/`Event`/`Semaphore` 查询，并且把查询放在独立线程里，超时后放弃该句柄继续。**注意：无法真正取消这类阻塞调用，只能隔离线程后泄漏它。**
2. **非提权进程可能读不到对象名。** Windows 8 起，读取其他进程的内核对象名需要足够的完整性级别。拿不到名字时按降级策略处理。

**降级策略**：命名空间判定失败时，不猜——改为**用结果反推**。即跳过静态判定，直接进入实测（见第 6 节）：如果第二账户下能起来第二个实例，说明锁是会话级的。这比猜一个置信度更高的结论。

### 3.4 注册表配置探测（辅助打分）

扫 `HKCU\Software\<Vendor>\<App>` 是否存在。

- 存在 → 提示"通道 B 可能不彻底，注册表里仍有共享状态"，把通道 B 的置信度下调一档。
- 不存在 → 不影响。

这一层只调整置信度，不单独决定结论。

---

## 4. 数据模型：软件画像

```json
{
  "schema": 1,
  "name": "QQ",
  "exe": "C:\\Program Files\\Tencent\\QQNT\\QQ.exe",
  "exe_resolved": "C:\\Program Files\\Tencent\\QQNT\\QQ.exe",
  "kernel": {
    "type": "electron",
    "confidence": "high",
    "score": 9,
    "evidence": [
      "versions\\9.9.33-52230\\icudtl.dat",
      "versions\\9.9.33-52230\\resources\\app.asar",
      "versions\\9.9.33-52230\\libEGL.dll"
    ],
    "note": "顶层 QQ.exe 是启动壳，Electron 负载在 versions\\<ver>\\ 下"
  },
  "install": {
    "scope": "machine",
    "dir": "C:\\Program Files\\Tencent\\QQNT",
    "users_readable": true,
    "evidence": "继承自 C:\\Program Files 的 BUILTIN\\Users:(RX)"
  },
  "registry": {
    "checked": ["HKCU\\Software\\Tencent\\QQ"],
    "found": ["HKCU\\Software\\Tencent\\QQ"],
    "impact": "may_reduce_isolation"
  },
  "single_instance": {
    "mechanism": ["named_mutex"],
    "namespace": "session",
    "confidence": "medium",
    "note": "非提权进程未能读到对象名，按启动前后 Mutant 计数差值推断"
  },
  "verdict": {
    "level": "green",
    "recommend": "B",
    "fallback": "A",
    "reason": "Electron 内核对 --user-data-dir 支持概率高，且不占用第二个账户",
    "requires_runtime_check": true
  }
}
```

**字段约定**

- 每个探测结论都必须带 `confidence` 与 `evidence`。没有证据的结论不允许出现在输出里。
- `requires_runtime_check` 为真时，界面必须提示"该结论需要实测确认后才能执行"。

---

## 5. 决策矩阵

| 内核实测 | 安装作用域 | 访问权限 | 锁命名空间 | 结论 |
|---|---|---|---|---|
| Electron/Chromium 高分 | 任意 | 任意 | 任意 | **绿 · 走 B**（需实测确认参数生效） |
| Electron/Chromium 低分 | machine | — | session | **绿 · 走 A** |
| Electron/Chromium 低分 | machine | — | global | 红（通道 A 无效） |
| Electron/Chromium 低分 | user | 有读执行 | session | **黄 · 走 A**（注意路径与凭据） |
| Electron/Chromium 低分 | user | 无读执行 | — | 红（通道 A 不可用） |
| 参数实测失败 | machine | — | session | 回退 **绿 · 走 A** |
| 任意 | 任意 | 任意 | 任意，但目标需提权 | 红 |

**优先级规则**：当两条通道都可用时，**默认推荐 B**——它不占用第二个账户、不需要密码、可以开多个实例。通道 A 作为兜底。

**红线的说明**：判红不是失败，是诚实。告诉用户"这条路走不通，别折腾了"比给一个会闪退的图标有用得多。

---

## 6. 实测校验协议（通道 B 专用）

静态探测只能给出候选，实测才是定论。

```
前置：向用户声明会短暂打开 1–2 个目标软件窗口，获得确认后执行。

1. 记录测试前目标进程的 PID 集合 P0
2. 用 --<profile-flag> "<tempdir1>" 启动实例 #1
3. 等待 T1（默认 8 秒），确认 #1 存活且 PID ∉ P0
4. 用 --<profile-flag> "<tempdir2>" 启动实例 #2
5. 等待 T2（默认 8 秒）
6. 判定：
     两个实例都存活        → 参数有效，置信度 high，通道 B 可用
     仅 #1 存活，#2 已退出  → 参数被忽略（很可能是 userData 硬编码），回退通道 A
     #1 也退出了           → 探测干扰了原实例，立即中止并如实报告
7. 清理：关闭测试实例；临时 profile 目录默认保留（供用户查看），可配置为自动删除
```

**为什么必须是实测**：`app.setPath('userData', 硬编码)` 这一类写法在静态层面完全看不出来。已经有开源项目记录过这个反例（见 [PRIOR-ART.md](PRIOR-ART.md) 中的 Codex 案例）。

---

## 7. 执行层

### 7.1 通道 A：多用户会话

```c
BOOL CreateProcessWithLogonW(
  LPCWSTR        lpUsername,        /* 目标账户名，如 L"10"            */
  LPCWSTR        lpDomain,          /* L"." 表示本机                    */
  LPCWSTR        lpPassword,
  DWORD          dwLogonFlags,      /* LOGON_WITH_PROFILE = 0x1        */
  LPCWSTR        lpApplicationName,
  LPWSTR         lpCommandLine,
  DWORD          dwCreationFlags,   /* CREATE_UNICODE_ENVIRONMENT      */
  LPVOID         lpEnvironment,
  LPCWSTR        lpCurrentDirectory,/* 必须设为 exe 所在目录            */
  LPSTARTUPINFOW lpStartupInfo,
  LPPROCESS_INFORMATION lpProcessInformation
);
```

`advapi32.dll` 导出。**不需要管理员权限**，前提是目标账户是标准用户。

**为什么不用 `runas /savecred`**

| | `runas /savecred` | `CreateProcessWithLogonW` |
|---|---|---|
| 用户配置文件加载 | 隐式，不稳定 | `LOGON_WITH_PROFILE` 明确加载 |
| `%USERPROFILE%` 环境变量 | 可能不展开 | 正确指向目标账户 |
| 出错表现 | 控制台黑窗一闪即没 | 返回明确 Win32 错误码 |
| 凭据管理 | 交给系统凭据管理器，程序无法管理 | 自行管理，可加密、可轮换、可清除 |
| 依赖 | 需拉起 `seclogon` 服务 | 无需额外服务 |

**常见错误码与处置**

| 错误码 | 常量 | 含义 | 处置 |
|---|---|---|---|
| 1326 | `ERROR_LOGON_FAILURE` | 密码错误 | 提示重新输入密码 |
| 1327 | `ERROR_ACCOUNT_RESTRICTION` | 账户受限制（如空密码 + 限制策略） | 提示给该账户设密码 |
| 1385 | `ERROR_LOGON_TYPE_NOT_GRANTED` | 该账户未被允许此登录类型 | 检查"允许本地登录"策略 |
| 1314 | `ERROR_PRIVILEGE_NOT_HELD` | 缺少令牌相关特权 | 本场景通常不会出现；若出现如实报错 |

**凭据存储**：`CryptProtectData`（`crypt32.dll`，DPAPI，用户作用域）加密后写入 `config.json`。同一台机器、同一账户可解密；换机器或换账户解不开。明文密码绝不落盘。

### 7.2 通道 B：独立配置目录

```
CreateProcessW(
  exe,
  "\"<exe>\" --<profile-flag> \"<profile_dir>\"",
  ... )
```

要点：

- **工作目录设为 exe 所在目录**——部分程序依赖相对路径加载资源。
- profile 目录默认 `%LOCALAPPDATA%\twinlaunch\profiles\<slug>\`，允许改到其他盘。
- 参数名不一定是 `--user-data-dir`。Electron 通用该参数；Firefox 系用 `-profile`；其他程序需按探测结果或用户手动指定。

### 7.3 图标生成

```
CoInitialize(NULL)
CoCreateInstance(CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, IID_IShellLinkW, &pLink)
pLink->SetPath(<我们的启动器>)
pLink->SetArguments("--target \"<原exe>\"")
pLink->SetIconLocation(<原exe>, 0)          /* 沿用原程序图标 */
pLink->SetWorkingDirectory(<原exe 目录>)
pLink->QueryInterface(IID_IPersistFile, &pFile)
pFile->Save(<桌面路径>.lnk, TRUE)
```

**实测结论**：纯 `ctypes` 走 `CoInitialize` + `CoCreateInstance` 返回 `S_OK`，不需要 `pywin32` 之类的第三方依赖。这意味着"零依赖"目标是可以达成的。

---

## 8. 已知陷阱清单

| 陷阱 | 现象 | 处理 |
|---|---|---|
| 快捷方式目标是环境变量形式 | 以第二账户身份去找 `C:\Users\<b>\AppData\...`，文件不存在，进程秒退 | 解析后立即展开环境变量 |
| per-user 安装 | 第二账户看不到 exe | 探测阶段直接判黄/红 |
| 系统凭据管理器残留旧密码 | 改了账户密码后一直报密码错 | 通道 A 自管密码，不使用系统凭据；提供"清除凭据"入口 |
| Electron 负载在版本子目录 | 只看同级目录会误判为原生 | 递归搜索 `versions\*` / `Application\*` |
| `NtQueryObject` 查对象名阻塞 | 探测线程卡死，界面无响应 | 只查三种类型；放独立线程；超时放弃 |
| 非提权读不到对象名 | 命名空间判定失败 | 降级为"实测反推"，不猜 |
| `app.setPath('userData', 硬编码)` | 参数法看似支持，第二个实例实际秒退 | 通道 B 强制实测校验 |
| 程序依赖相对路径 | 双开后共享同一份数据 | 启动时显式设置工作目录 |
| `Global\` 命名空间的锁 | 通道 A 完全无效 | 探测阶段判红，如实告知 |

---

## 9. 技术选型

**环境约束（开发机实测）**

- 可用的三个 Python（3.12.10 / 3.13.12 / system）**均缺 `tkinter`**。
- `csc.exe` 与 PowerShell `Add-Type` 在开发沙箱内被安全策略拦截，**无法验证 C# 编译产物**。
- Python `ctypes` 调用 COM **可用**（`CoInitialize` → `CoCreateInstance(CLSID_ShellLink)` 返回 `S_OK`）。

**候选方案**

| 方案 | 优点 | 缺点 |
|---|---|---|
| Python + ctypes 自绘 Win32 窗口 | 引擎与界面同语言；零依赖；开发环境内可验证 | 界面代码量大 |
| Python 引擎 + PowerShell/WinForms 外壳 | 界面代码量最小，原生观感 | 两套语言；受执行策略影响，需 `.cmd` 包装 |
| C# + `csc.exe` 编译单文件 exe | 单个 exe，用户体验最好 | 开发环境内无法验证编译结果 |
| Python + tkinter | 界面代码最少 | 需引入带 tkinter 的解释器，破坏"零依赖" |

**结论**：**引擎先用 Python 纯标准库写成 CLI，界面选型推迟到 M3。** 引擎与界面语言不绑定——界面层只是调用引擎暴露的接口，将来完全可以用 C# 重写外壳。

---

## 10. 安全与隐私边界

- 密码仅以 DPAPI 密文形式存储于本机，不明文落盘、不外传。
- 不读取、不修改目标程序的文件与内存。
- **探测阶段零写入**；所有副作用动作需用户显式确认。
- 不请求管理员权限。需要提权的软件直接判红。
- 无遥测、无统计上报、无广告、无捆绑。
- 实测校验会短暂打开目标软件窗口，**必须事先声明并取得确认**，不得静默执行。

---

## 11. 里程碑与验收标准

### M0 · 探测 CLI（当前）

- 输入：任意 exe 路径
- 输出：软件画像 JSON + 人类可读报告
- 验收：
  - `C:\Program Files\Tencent\QQNT\QQ.exe` → `electron / machine / green-B`
  - `C:\Users\<user>\AppData\Local\Programs\WorkBuddy\WorkBuddy.exe` → `electron / user / yellow-B`
  - 纯原生程序（如 `notepad.exe`）→ `native`
- 硬约束：**全程只读**，不产生任何副作用

### M1 · 通道 A 落地

- 验收：双击生成的图标直接开出第二个实例，不弹密码框；图标沿用原程序外观

### M2 · 通道 B 落地

- 验收：Electron 软件双开成功；实测协议能正确识别"参数被忽略"的情况并回退到通道 A

### M3 · 图形界面

- 验收：软件列表、搜索、自检报告、图标管理全流程无需命令行

### M4 · 进阶

- 多账户 N 开、便携模式、图标批量迁移
