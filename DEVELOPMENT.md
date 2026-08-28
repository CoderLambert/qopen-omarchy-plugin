# QOpen 插件开发记录

本文记录 QOpen 从个人命令行启动器演进为 Omarchy Shell 插件的过程、关键技术
决策、事故复盘、验证方式和后续维护约定。用户安装与使用说明请查看
[README.md](README.md) 或 [README.zh-CN.md](README.zh-CN.md)。

## 1. 产品边界

QOpen 的定位是“个人统一资源启动层”，不是桌面应用索引。

它负责：

- 用户主动维护的项目目录与文件；
- 高频使用且经过筛选的技术文档和网站；
- TUI、显式命令和 SSH 目标；
- 资源分组、描述、收藏和稳定 id；
- 在 Omarchy 菜单、快捷键和状态栏之间提供同一入口。

它不负责：

- 扫描所有 `.desktop` 应用；
- 索引整个文件系统；
- 保存密码、令牌、SSH 私钥等秘密；
- 替代 Omarchy 自带的应用和命令搜索；
- 从 QML 拼接并执行任意 shell 字符串。

## 2. 版本演进

### v1：CLI 与 JSON 资源模型

第一阶段建立了可移植的 `config.json` 数据模型与 Python CLI：

- 支持 `web`、`file`、`project`、`tui`、`command`、`ssh`；
- 使用稳定 id 作为启动和更新键；
- 通过 Omarchy 菜单组件完成引导式新增和编辑；
- 为文件和项目提供剪贴板粘贴与路径预检查；
- 启动行为统一走 Omarchy helper 或 `xdg-*` 兼容路径。

这一阶段确认 JSON 目录应独立于界面实现，保留在
`~/.config/qopen/config.json`。

### v2.0：Omarchy Shell 插件化

QOpen 被拆分为标准用户插件：

- `manifest.json` 声明 `menu` 与 `bar-widget`；
- `QOpen.qml` 负责搜索、分组、收藏和资源列表；
- `BarWidget.qml` 提供状态栏入口；
- Python 后端保留验证、写入与启动职责；
- 原有 CLI 保留，避免 UI 迁移破坏脚本和肌肉记忆。

同时加入一组高价值前端参考资源，按 TanStack、框架、UI、工具链、测试、
React 富文本、动画、图标、状态、表单和交互能力分组。

### v2.1：原生新增/编辑体验

第二轮重点解决新增和编辑体验：

- 新增 `ResourceEditor.qml` 单页表单；
- 根据资源类型显示 URL、项目目录、文件、命令或 SSH 字段；
- 修复 project 类型只有 Name/ID、没有路径字段的问题；
- 使用普通 `TextField`，恢复系统剪贴板粘贴；
- 增加 Paste 和 Check 操作；
- 自动推导 Name、id、默认分组和图标；
- 后端增加 JSON CRUD API，并继续使用锁、备份与原子替换。

### v2.2：原生 Qt 文件选择器尝试

为了降低路径输入成本，曾接入 Qt `FileDialog` 与 `FolderDialog`：

- file 类型限制选择普通文件；
- project 类型限制选择目录；
- `file://` URI 在写入前转换为本地路径；
- 独立选择器窗口通过精确 Hyprland 规则浮动居中。

功能层面验证通过，但该方案把 Qt 的平台文件对话框、GTK、GIO 和 GVFS 加载进
了长时间运行的共享 Quickshell 进程，最终证明风险不可接受。

### v2.3：安全内嵌路径浏览器

2.3 完全移除 `QtQuick.Dialogs`，新增 `PathPicker.qml`：

- 浏览器嵌入 QOpen 自身，不创建 GTK 文件窗口；
- Python 使用一次性 `os.scandir()` 返回排序后的目录快照；
- 不注册 GIO/GVFS 目录监视器；
- project 模式只返回目录；
- file 模式返回目录和普通文件；
- 支持 Home、上级目录、路径输入、隐藏项和键盘导航；
- 单次列表最多返回 1000 项，避免异常目录拖垮 UI；
- 移除 v2.2 专用 Hyprland 窗口规则。

## 3. v2.2 文件选择器事故复盘

### 现象

打开 Qt 原生文件或目录选择器后，Omarchy Shell 会退出并由 Quickshell 自动重启。
GLib 日志显示 `failed to allocate 4 bytes`，但系统仍有约 52 GiB 可用内存，
用户 cgroup 没有限额，OOM 计数为零。

### 证据

检查 `systemd-coredump` 后发现同一测试时段共有 5 次历史 Quickshell dump：

- 3 次 `SIGABRT` 的调用链一致：Qt 文件对话框进入 GTK/GIO，GVFS 通过 D-Bus
  创建目录监视器，随后 GLib 主动 abort；
- 2 次 `SIGSEGV` 发生在插件多文件热重载期间，栈位于 Qt QML 表达式执行路径；
- 配置文件在原生选择器崩溃前没有被写入；
- Quickshell 均自动重启，没有发现用户数据丢失。

### 可以证明与不能证明的部分

可以证明：

- 原生选择器重复进入 GTK/GIO/GVFS 路径；
- 多次 `SIGABRT` 与打开 QOpen 选择器时间一致；
- 不是系统级内存耗尽；
- 删除原生对话框后，连续打开内嵌浏览器没有新增 core。

不能仅凭 core 证明：

- GLib 为何无法完成极小内存分配；
- 根因具体属于 Qt、GTK、GIO、GVFS 或它们之间的状态交互；
- QML 热重载的两个 `SIGSEGV` 是否与同一个上游缺陷有关。

### 决策

不在插件中绕过、捕获或重试原生对话框，因为它与 Omarchy Shell 同进程，崩溃
边界等于整个桌面 Shell。正确修复是移除该依赖链。

开发同步也改为：先完成源码多文件修改，再一次性同步，最后执行一次
`omarchy restart shell`，避免让热重载观察到中间状态。

## 4. 当前架构

```text
QOpen.qml
  ├─ 搜索、分组、收藏、列表与路由
  ├─ ResourceEditor.qml
  │    ├─ 类型感知表单
  │    ├─ 本地校验与状态提示
  │    └─ PathPicker.qml
  │         ├─ 路径与列表交互
  │         └─ api browse-path
  └─ Process argv
          |
          v
      bin/qopen
        ├─ JSON schema 验证
        ├─ 目录枚举
        ├─ 文件锁
        ├─ 备份与原子替换
        └─ 资源启动分发
```

### QML 职责

- 展示与主题；
- 键盘、鼠标和焦点状态；
- 搜索、排序和筛选；
- 构造 JSON payload；
- 使用参数数组启动后端。

### Python 职责

- 路径、URL 和命令参数规范化；
- 目录读取和边界限制；
- 完整配置 schema 验证；
- 并发锁、备份、原子写入；
- 调用 Omarchy/xdg 启动 helper；
- 输出机器可读 JSON API。

## 5. 目录说明

| 文件 | 作用 |
| --- | --- |
| `manifest.json` | Omarchy 插件元数据与入口声明 |
| `QOpen.qml` | 主界面、搜索、资源列表、路由与 CRUD 协调 |
| `ResourceEditor.qml` | 新增/编辑表单 |
| `PathPicker.qml` | 安全内嵌文件和目录浏览器 |
| `BarWidget.qml` | Omarchy 状态栏按钮 |
| `bin/qopen` | Python CLI、机器 API、持久化与启动后端 |
| `README.md` | 用户安装、使用与排障文档 |
| `DESIGN.md` | 产品边界与稳定架构说明 |
| `DEVELOPMENT.md` | 开发历史、事故复盘与维护流程 |
| `CHANGELOG.md` | 用户可见版本变更 |

## 6. 数据与写入安全

### 写入流程

1. QML 将编辑结果序列化为 JSON 参数。
2. 后端读取当前配置并取得独占文件锁。
3. 在副本上执行 mutation。
4. 验证完整配置，而不只验证当前 item。
5. 将旧配置复制为 `config.json.bak`。
6. 在配置同目录创建临时文件并 `fsync`。
7. 使用 `os.replace` 原子替换。
8. 对配置目录执行 `fsync`。

### 命令边界

QML 只传递 argv，不拼接 shell 命令。`tui` 和 `command` 在 JSON 中使用参数数组。
后端仅在交互式文本输入时通过 `shlex.split` 转换一次，然后仍以 argv 执行。

### 路径浏览 API

```bash
bin/qopen api browse-path \
  --path ~/Code \
  --type project
```

返回：

```json
{
  "ok": true,
  "result": {
    "path": "/home/user/Code",
    "parent": "/home/user",
    "entries": [
      {
        "name": "example",
        "path": "/home/user/Code/example",
        "kind": "directory",
        "hidden": false,
        "symlink": false
      }
    ],
    "truncated": false
  }
}
```

该 API 只读目录，不创建、删除或修改文件。

## 7. 路由协议

Omarchy Shell 通过 JSON payload 打开插件：

```bash
omarchy-shell shell toggle qopen.launcher '{}'
omarchy-shell shell toggle qopen.launcher '{"favorites":true}'
omarchy-shell shell toggle qopen.launcher '{"group":"projects"}'
omarchy-shell shell toggle qopen.launcher '{"action":"add"}'
omarchy-shell shell toggle qopen.launcher \
  '{"action":"add","type":"file","browse":true}'
omarchy-shell shell toggle qopen.launcher \
  '{"action":"edit","item":"react"}'
```

路由 payload 只改变界面初始状态，不直接写配置。

## 8. 本地开发流程

### 基础检查

```bash
omarchy plugin validate .
./bin/qopen --version
./bin/qopen --doctor
python -m unittest discover -s tests -v
```

目录 API：

```bash
./bin/qopen api browse-path --path "$PWD" --type project | jq
./bin/qopen api browse-path --path "$PWD" --type file | jq
```

### 隔离配置测试

不要在 CRUD 测试中使用真实个人目录。通过 `QOPEN_CONFIG` 指向临时文件：

```bash
qopen_test_dir=$(mktemp -d)
QOPEN_CONFIG="$qopen_test_dir/config.json" ./bin/qopen add project \
  --name "Fixture" \
  --target "$qopen_test_dir"
QOPEN_CONFIG="$qopen_test_dir/config.json" ./bin/qopen --list
```

测试完成后删除该明确的临时目录。

### 安装到用户插件目录

在源码验证完成后，将仓库内容同步到：

```text
~/.config/omarchy/plugins/qopen.launcher/
```

多文件更新应一次性完成，然后执行：

```bash
omarchy restart shell
```

不要修改 `/usr/share/omarchy` 下的第一方文件。

### 运行时检查

至少验证：

- 主搜索界面打开且输入框获得焦点；
- 六种类型都显示正确字段；
- project 浏览器只显示目录；
- file 浏览器可以进入目录并接受文件；
- 选择结果自动推导 Name 和 id；
- Check 返回正确存在状态；
- 取消操作不改变配置哈希；
- 新增、更新、收藏与删除均产生合法 JSON；
- `journalctl --user` 没有新的 QML error；
- `coredumpctl list` 没有新增 Quickshell core。

## 9. v2.3 发布验证记录

发布前完成了以下验证：

- 源码和已安装插件目录完全一致；
- 两个目录枚举模式均返回合法 JSON；
- 文件选择后表单填入绝对路径并显示 `File exists`；
- 自动推导文件名称；
- 文件和项目浏览器交替打开/取消 8 次；
- 原生 GTK 文件选择窗口数量为 0；
- Quickshell 历史 core 数量测试前后保持不变；
- 用户配置恢复并保持预期 SHA-256；
- `qopen --doctor`、manifest validation、Hyprland config validation 通过。

## 10. 发布流程

1. 更新 `manifest.json` 版本。
2. 更新 `VERSION` 常量。
3. 更新 `CHANGELOG.md`。
4. 检查 README 的当前版本与兼容性说明。
5. 运行 manifest、CLI、目录 API 和 UI 验证。
6. 搜索绝对路径、凭据、测试数据和生成文件。
7. 确认源码与用户安装副本一致。
8. 创建 Git commit。
9. 推送 GitHub。
10. 验证公开仓库、默认分支和 clone URL。

## 11. 已知限制与后续方向

- 当前目录列表上限为 1000 项，没有分页。
- 路径浏览器只处理本地文件系统，不支持远程 GVFS mount URI。
- 编辑时资源 type 固定，避免隐式丢失类型专有字段。
- JSON API 目前服务于插件自身，尚未承诺跨版本稳定。
- 使用频率排序、导入导出 preset、资源复制和模板仍属于后续功能。

## 12. 维护原则

- 保持个人目录与插件代码解耦；
- 不把用户资源数据提交到仓库；
- 不在共享 Shell 进程中引入高风险原生集成；
- 每个写操作必须可验证并有备份；
- 事故结论区分“证据证明”和“合理推断”；
- Omarchy 第一方目录始终只读。
