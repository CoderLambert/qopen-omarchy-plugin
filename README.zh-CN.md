# QOpen for Omarchy（中文文档）

QOpen 是运行在 [Omarchy](https://omarchy.org/) 上的个人统一资源启动层。它把项目目录、文件、技术文档、前端生态网站、TUI、命令和 SSH 目标集中到一个可搜索、键盘优先的界面中。

QOpen 不是应用索引器，也不会扫描整个 home 目录。目录中的每一项都由你主动维护，可以写描述、分组、收藏，并通过稳定的 id 快速打开。

**当前版本：2.3.0** · [English README](README.md) · [开发记录](DEVELOPMENT.md)

## 为什么需要 QOpen

Omarchy 本身已经很擅长启动已安装的桌面应用和 Shell 命令。QOpen 解决的是应用索引不适合表达的那一层个人资源：

- 每天都会进入的项目目录；
- 需要用终端编辑器打开的配置文件；
- 经过筛选、值得长期保留的框架或库文档；
- 希望有清晰名称和分组的 TUI；
- 显式、安全的命令入口；
- 与同一环境其他资源放在一起的 SSH 目标。

目录始终保持小而明确：QOpen 不扫描整个 home 目录，也不会静默加入资源。

## 使用截图

![QOpen 使用截图：按 React 搜索并按集合查看资源](docs/assets/qopen-usage.png)

截图展示了输入 `react` 后的搜索界面：左侧按集合筛选，右侧显示匹配资源；每一项都可以直接打开、收藏、复制目标、编辑或删除。

## 功能概览

- 按名称、描述、id、类型、分组、目标和命令搜索。
- 按集合查看资源，并提供全部资源和收藏视图。
- 支持 `web`、`project`、`file`、`tui`、`command`、`ssh` 六种资源类型。
- 新增和编辑使用单页表单，根据类型显示对应字段。
- project 和 file 使用内嵌路径浏览器，不调用 GTK/GIO/GVFS 原生文件对话框。
- 路径输入支持常规粘贴，也提供明确的 Paste 按钮。
- 自动推导名称、id、默认分组和图标，并在保存前进行校验。
- 收藏、复制目标、编辑和删除操作都在资源行内完成。
- 配置写入使用锁、备份和同目录原子替换，避免留下半截 JSON。
- 可选状态栏组件：左键打开全部资源，右键打开收藏。
- 保留 CLI，方便脚本、批量维护和故障诊断。

## 环境要求

- 支持当前 Omarchy Shell 插件命令的 Omarchy。
- Omarchy 提供的 Quickshell。
- Python 3.10 或更高版本。
- 用于显示内置图标的 Nerd Font。
- `wl-clipboard`（提供 `wl-paste` 和 `wl-copy`），用于剪贴板操作。

QOpen 会优先使用 Omarchy 提供的启动 helper，可以通过下面的命令检查当前完整环境：

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen --doctor
```

2.3.0 发布版本在 Omarchy 4.0.1、Quickshell 0.3.1 和 Qt 6.11.2 上完成开发与验证；这些是已测试版本，不是严格版本锁定。

## 安装

安装前建议先查看仓库源码。Omarchy Shell 插件运行在共享的长生命周期 Shell 进程中，并不是沙箱程序。

```bash
omarchy plugin add https://github.com/CoderLambert/qopen-omarchy-plugin.git --enable
```

确认源码后，也可以使用非交互安装：

```bash
omarchy plugin add https://github.com/CoderLambert/qopen-omarchy-plugin.git --enable --yes
```

插件 id 是 `qopen.launcher`。如果安装时没有启用，可稍后启用状态栏组件：

```bash
omarchy plugin enable qopen.launcher --section left
```

安装后检查环境：

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen --doctor
omarchy plugin validate ~/.config/omarchy/plugins/qopen.launcher
```

## 配置入口

### 推荐快捷键

在 `~/.config/hypr/bindings.lua` 中加入：

```lua
o.bind(
  "SUPER + ALT + O",
  "QOpen resource search",
  "omarchy-shell shell toggle qopen.launcher '{}'"
)
```

保存后执行：

```bash
hyprctl reload
hyprctl configerrors
```

之后按 `Super + Alt + O` 即可打开搜索页面。

### 加入 Omarchy 菜单

编辑 `~/.config/omarchy/extensions/omarchy-menu.jsonc`，将下面的条目加入根对象。保存后菜单扩展会自动热加载：

```jsonc
"custom-qopen": {
  "icon": "󰖟",
  "label": "QOpen",
  "description": "Projects, documentation, files and tools",
  "aliases": ["qopen", "resources"]
},

"custom-qopen.open": {
  "icon": "󰍉",
  "label": "Open QOpen",
  "description": "Grouped personal resource launcher",
  "action": "omarchy-shell shell toggle qopen.launcher '{}'"
},

"custom-qopen.favorites": {
  "icon": "",
  "label": "Favorites",
  "description": "Frequently used personal resources",
  "action": "omarchy-shell shell toggle qopen.launcher '{\"favorites\":true}'"
},

"custom-qopen.add": {
  "icon": "",
  "label": "Add Resource",
  "description": "Web, project, file, TUI, command or SSH",
  "action": "omarchy-shell shell toggle qopen.launcher '{\"action\":\"add\"}'"
}
```

## 打开方式与路由

直接打开搜索界面：

```bash
omarchy-shell shell toggle qopen.launcher '{}'
```

也可以在打开时指定初始视图：

```bash
# 收藏
omarchy-shell shell toggle qopen.launcher '{"favorites":true}'

# 指定集合
omarchy-shell shell toggle qopen.launcher '{"group":"projects"}'

# 打开新增表单
omarchy-shell shell toggle qopen.launcher '{"action":"add"}'

# 直接打开 project 新增并进入路径浏览器
omarchy-shell shell toggle qopen.launcher \
  '{"action":"add","type":"project","browse":true}'

# 打开指定资源的编辑表单
omarchy-shell shell toggle qopen.launcher \
  '{"action":"edit","item":"react"}'
```

路由参数只决定界面初始状态，不会绕过表单验证直接修改配置。

## 日常使用

### 搜索和集合

1. 按 `Super + Alt + O`，或从菜单/状态栏打开 QOpen。
2. 直接输入关键词；默认会在当前集合中搜索。
3. 用鼠标点击左侧集合，或使用 `Up`/`Down` 移动选择。
4. 按 `Enter` 打开当前资源。

集合是资源的 `group` 字段。常见的组织方式包括 `projects`、`frameworks`、`ui`、`testing`、`tools` 和 `docs`。集合名称和数量会根据目录实时显示。

### 主界面快捷键

| 按键 | 操作 |
| --- | --- |
| 输入或粘贴 | 搜索当前集合 |
| `Up` / `Down` | 移动资源选择 |
| `Enter` | 打开选中的资源 |
| `Escape` | 依次清除搜索、关闭编辑器、关闭 QOpen |
| `Ctrl+N` | 新增资源 |
| `Ctrl+E` | 编辑选中资源 |
| `Ctrl+D` | 确认后删除选中资源 |
| `Ctrl+R` | 重新加载目录 |
| `Ctrl+Enter` | 编辑时保存 |

### 新增或编辑资源

1. 按 `Ctrl+N`，或点击右上角 `+ Add`。
2. 选择资源类型。
3. 填写名称、id、分组和目标；类型不同，目标字段也不同。
4. 对 file/project 类型，可以直接粘贴路径，也可以点击 Browse 使用内嵌浏览器。
5. 点击 Check 检查目标是否存在，再点击 Save。

编辑时资源类型固定，避免切换类型时悄悄丢失专用字段。如果从路径浏览器选择目标，名称和 id 会根据路径自动补全，仍可以在保存前手动修改。

### 内嵌路径浏览器

QOpen 的路径浏览器嵌在自己的界面内，不会弹出系统文件选择窗口：

| 按键 | 操作 |
| --- | --- |
| `Up` / `Down` | 选择目录或文件 |
| `Enter` | 进入目录，或选择文件 |
| `Alt+Up` | 打开上级目录 |
| `Ctrl+L` | 聚焦路径输入框 |
| `Ctrl+H` | 显示/隐藏隐藏项 |
| `Escape` | 返回资源表单 |

project 模式只显示目录，并使用底部按钮选择当前目录；file 模式同时显示目录和普通文件，双击文件可以立即选择。

路径字段支持 `~`、环境变量和绝对路径。实际展开由 Python 后端完成，不通过 shell 字符串插值执行。

## 六种资源类型

| 类型 | 必填目标 | 打开行为 |
| --- | --- | --- |
| `web` | HTTP(S) 地址 | 使用 Omarchy Web App 或默认浏览器 |
| `project` | 目录路径 | 在该目录打开终端 |
| `file` | 文件路径 | 使用配置的终端编辑器打开 |
| `tui` | 参数数组 | 通过 Omarchy TUI helper 打开 |
| `command` | 参数数组 | 脱离运行或在终端中运行 |
| `ssh` | 主机或 `user@host` | 在终端中运行 `ssh` |

推荐把同一用途的资源放进同一个集合。例如：

- `React · Rich Text`：Lexical、Tiptap 等富文本编辑器；
- `React · Motion`：Motion、React Spring 等动画方案；
- `React · Icons`：Lucide、React Icons 等图标库；
- `TanStack`：Query、Router、Start、Table 等；
- `Frameworks`：React、Vite、Next.js 等官方文档；
- `Testing`：Vitest、Playwright、Testing Library 等。

## 配置文件

默认目录位于：

```text
~/.config/qopen/config.json
```

示例：

```json
{
  "version": 1,
  "defaults": {
    "editor": "nvim",
    "webMode": "app"
  },
  "items": [
    {
      "id": "react",
      "name": "React Documentation",
      "type": "web",
      "group": "frameworks",
      "icon": "",
      "description": "Official React guides and API reference",
      "target": "https://react.dev/learn",
      "mode": "browser",
      "favorite": true
    },
    {
      "id": "my-app",
      "name": "My App",
      "type": "project",
      "group": "projects",
      "icon": "󰉋",
      "target": "~/Code/my-app"
    },
    {
      "id": "lazygit",
      "name": "Lazygit",
      "type": "tui",
      "group": "tools",
      "command": ["lazygit"]
    }
  ]
}
```

约束和安全保证：

- id 只能包含小写字母、数字、`_` 和 `-`，并且必须唯一；
- 每次新增、编辑、收藏和删除都会验证完整目录；
- 写入前会将旧版本保存为 `config.json.bak`；
- 使用文件锁和同目录原子替换，不会由 QML 直接写 JSON；
- 资源数据不会自动同步到 GitHub 仓库。

如需使用另一份目录，可以设置 `QOPEN_CONFIG`：

```bash
QOPEN_CONFIG=~/Documents/qopen-work.json \
  ~/.config/omarchy/plugins/qopen.launcher/bin/qopen --list
```

## CLI

```bash
QOPEN=~/.config/omarchy/plugins/qopen.launcher/bin/qopen

$QOPEN                  # 交互式资源选择器
$QOPEN --groups         # 按集合浏览
$QOPEN --favorites      # 浏览收藏
$QOPEN --list           # 输出全部资源
$QOPEN <id>             # 打开指定资源
$QOPEN add              # 引导式新增
$QOPEN edit [id]        # 引导式编辑
$QOPEN remove [id]      # 确认后删除
$QOPEN favorite <id> toggle  # 切换收藏
$QOPEN --edit           # 用编辑器打开原始 JSON
$QOPEN --doctor        # 检查依赖和全部资源
$QOPEN --version
```

非交互新增示例：

```bash
$QOPEN add project \
  --id qopen \
  --name "QOpen Plugin" \
  --group projects \
  --target ~/Code/qopen-omarchy-plugin \
  --favorite
```

`api` 子命令是 QML 使用的机器接口，当前主要服务于插件自身，暂不承诺跨版本的公共稳定性。

## 架构与安全

```text
Omarchy 菜单 / 快捷键 / 状态栏
                 |
                 v
             QOpen.qml
                 |
       +---------+----------+
       |                    |
ResourceEditor.qml     PathPicker.qml
       |                    |
       +---------+----------+
                 | 仅传 argv
                 v
              bin/qopen
                 |
         配置锁 + 完整校验
                 |
                 v
       ~/.config/qopen/config.json
```

QML 负责界面、焦点和交互；Python 负责目录枚举、规范化、完整配置校验、持久化和进程分发。

内嵌路径浏览器刻意避开 Qt `FileDialog`、GTK、GIO 和 GVFS。QOpen 运行在共享的 Omarchy Shell 进程内，因此原生文件选择器一旦故障可能连带终止整个桌面 Shell。2.2 曾短暂使用原生对话框；2.3 在复现 Quickshell 崩溃后将其移除。证据、事故复盘和发布验证记录见 [DEVELOPMENT.md](DEVELOPMENT.md)。

命令始终以参数数组传递；QML 不会把资源值拼接成 shell 命令执行。

## 更新和卸载

更新通过 Git 安装的插件：

```bash
omarchy plugin update qopen.launcher --yes
```

卸载插件：

```bash
omarchy plugin remove qopen.launcher --yes
```

卸载不会删除 `~/.config/qopen/config.json`，重新安装后仍可继续使用个人目录。

## 排障

### QOpen 不显示

```bash
omarchy plugin validate ~/.config/omarchy/plugins/qopen.launcher
omarchy-shell shell rescanPlugins
omarchy restart shell
```

### 资源无法打开

运行 doctor 并检查失败的资源：

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen --doctor
```

project/file 类型请确认展开后的路径存在；tui/command 类型请确认命令的第一个可执行文件在 `PATH` 中。

### 配置损坏或新增失败

QOpen 会拒绝部分或格式错误的写入。先检查：

```text
~/.config/qopen/config.json
~/.config/qopen/config.json.bak
```

备份文件是上一次成功修改前的目录状态。若新增失败，优先检查 id 是否重复、id 是否含有大写或空格、目标字段是否已填写，以及当前用户是否有目标路径的访问权限。

### 开发热重载问题

Omarchy 通常会热重载 `~/.config/omarchy/plugins` 下的文件。多文件修改时，建议先一次性同步全部文件，再重启共享 Shell：

```bash
omarchy restart shell
```

这样可以避免插件文件处于中间状态时反复重建插件图。

## 开发

源码结构、版本演进、原生文件选择器事故、测试流程和发布记录见 [DEVELOPMENT.md](DEVELOPMENT.md)。用户可见变更见 [CHANGELOG.md](CHANGELOG.md)。

运行后端测试：

```bash
python -m unittest discover -s tests -v
```

## 许可

[MIT](LICENSE) © 2026 CoderLambert
