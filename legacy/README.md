# legacy/ — 当前主力方案（脚本版）

这是**正在实际使用**的双开方案，也是 twinlaunch 想做成软件前的**直接前身**。逻辑简单、可审计、零依赖，三个文件加起来不到 3KB。如果哪天要用图形界面或批量管理，再按 `docs/TECHNICAL.md` 的设计把它升级成正式工具；在那之前，**脚本就是够用的主力方案**。

## 文件

| 文件 | 作用 |
|---|---|
| `MakeUser10Icon.vbs` | 核心生成器：解析 `.exe` / `.lnk`，在桌面生成 `名称 (User10).lnk`，目标是 `cmd /c runas /savecred /user:10 "..." \|\| pause`（失败时窗口停留、错误可见） |
| `MakeUser10Icon.cmd` | 拖拽入口：把文件拖到这个 cmd 上即可调用 VBS |
| `Reset-User10-Password.cmd` | 一键重置本地账户 `10` 的密码；自带管理员自提升（UAC）；回车清空密码 / 输入新密码 |

## 原理

Windows 的 `runas /savecred` 会把凭据交给**凭据管理器**保管。第一次双击图标时输入一次 `10` 的密码，之后 Windows 永久代答，不再询问。第二个实例以用户 `10` 的身份跑在**同一个会话**里——对目标软件来说这就是另一台"电脑"，它的单实例锁（`Local\` 命名空间）天然不冲突，且**无需任何远程桌面**，两个窗口并排落在同一张桌面。

## 使用（两种入口）

1. **右键 → 发送到**：把 `Create User10 Dual Icon.cmd` 放进 `%APPDATA%\Microsoft\Windows\SendTo\`，以后右键任意 exe / 快捷方式 → 发送到 → 该项 → 桌面立即出现 `XXX (User10)` 图标。此入口文件未在本仓库（是安装在用户侧的那份副本）。
2. **拖拽**：把 exe / 快捷方式直接拖到 `MakeUser10Icon.cmd` 上。

首次双击新图标会弹一次密码框（`10` 的密码；若已清空则直接回车），之后永久免密。

## 本方案成立的前提（必须同时满足）

1. **软件装在全机可读位置**（`C:\Program Files\...` 等）。per-user 安装（`%LOCALAPPDATA%\Programs\...`）时用户 `10` 看不到 exe——如 WorkBuddy 即此类，此方案不适用（实测：其启动壳还额外屏蔽了 `--user-data-dir`，通道 B 也走不通，见 `docs/TECHNICAL.md`）。
2. 单实例锁是**会话级**（`Local\` 命名空间）。用 `Global\` 锁的软件，多用户会话同样冲突。
3. 软件不需要提权 / 不装内核驱动 / 不带反作弊（用户 `10` 只是 Users 组的标准用户）。

判断口诀：**看它的 exe 在不在 `C:\Program Files` 下**。在 → 绿，直接用；不在 → 黄/红，别折腾。

## 注意事项

- `10` 的密码被 `runas /savecred` 存在**凭据管理器**里（条目形如 `Domain:10`）。改密码后要删掉旧条目重新输一次，否则一直报密码错：
  ```
  cmdkey /delete:Domain:interactive=DESKTOP-6MQ1LCO\10
  ```
- 生成的图标目标是 `cmd /c runas ...`，右键菜单里的"以管理员身份运行"失效（`10` 是标准用户，用不上，正常）。
- C 盘是配了重启还原的 VHD：万一配置被还原，重新执行 `MakeUser10Icon.cmd` 重建图标即可；`Reset-User10-Password.cmd` 可随时重置密码。

## 第二账户的输入法（常见坑）

**现象**：双开出的第二个窗口里切不出中文输入法（系统输入法 / 微信输入法都试过）。

**根因**：输入法启用状态存在**每个用户自己的注册表 hive**（HKCU），而 `10` 的 profile 可能从未真正登录过（`C:\Users\10\NTUSER.DAT` 不存在，`ProfileList\SID` 的 `State=0`）。`runas` 不带 `/profile` 时用的是 DefaultUser 模板，配置全是默认值——所以**任何**以第二用户身份运行的双开方案都会遇到这个现象，不是本方案的 bug。

**系统输入法（微软拼音）**：以 `10` 身份登录一次（或在登录界面切换一次），设置 → 时间和语言 → 语言 → 添加中文即可。

**微信输入法（WeType）**：它走 TSF，机器级组件在 `C:\Program Files\Tencent\WeType\`（`wetype_tip.dll` 在 System32），但**每个用户要单独启用**，键在：
```
HKCU\Software\Microsoft\CTF\TIP\{86598FB9-66A2-463E-B9C2-AEB906D477AD}\LanguageProfile\0x00000804\{607FDF85-FCC8-4DBD-A365-41296F980C9C}
  Enable = 1
```
**注意 WeType 复用了微软拼音的 TIP GUID `{86598FB9-...}`**，只是 LanguageProfile 子键是微信自己的 `{607FDF85-...}`——别被迷惑。

**推荐做法**：先让 `10` 登录一次建好 profile，再运行 `Fix-User10-WeType.cmd`（以 `runas /savecred /profile /user:10` 自举，把 Enable 键写进 10 的 hive 并重启 WeType 进程）。

## 历史与血泪

- 初版图标直接抄了原快捷方式的目标字符串，没展开环境变量 → `%USERPROFILE%\AppData\...` 被 `runas` 当成 `C:\Users\10\AppData\...`，文件不存在，窗口秒退。已修复（VBS 里 `ExpandEnvironmentStrings`）。
- 凭据管理器残留旧密码（改密码前存的）导致登录被拒。已加 `cmdkey /delete` 步骤。
- WorkBuddy 实测走不通（启动壳拦截 `--user-data-dir`）→ 正是这个"为什么有些软件脚本帮不上"的活教材。
