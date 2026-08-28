# QOpen for Omarchy

QOpen is a personal resource launcher for [Omarchy](https://omarchy.org/). It
puts projects, files, documentation, web tools, terminal applications, commands
and SSH destinations behind one searchable, keyboard-first interface.

Unlike an application launcher, QOpen is intentionally curated: every item is
something you chose to keep, describe, group and find again.

> 中文简介：QOpen 是 Omarchy 上的个人统一资源启动层。它不是应用索引，
> 而是把项目目录、文件、常用文档、前端生态网站、TUI、命令和 SSH 目标集中到
> 一个支持搜索、分组、收藏与原生编辑的界面中。

Current release: **2.4.1**

**Documentation:** [简体中文](README.zh-CN.md) · [Development record](DEVELOPMENT.md)

## Highlights

- Native Omarchy Shell and Quickshell interface using live theme tokens.
- Search across name, description, stable id, type, group, target and command.
- Collections with counts, recommended ordering and a dedicated favorites view.
- Six resource types: web, project, file, TUI, command and SSH.
- Single-page add/edit form with type-aware fields and inline validation.
- Built-in file and directory browser that does not use GTK/GVFS file dialogs.
- Normal keyboard paste plus an explicit clipboard button for path fields.
- Automatic name, id, default group and icon inference where appropriate.
- Inline favorite, copy-target, edit and confirmed remove actions.
- Atomic JSON writes with locking and an automatic last-known-good backup.
- Validated backup recovery and explicit private-permission repair commands.
- Lossless editing of command arguments containing spaces or quotes.
- Optional bar widget: left-click opens all resources; right-click opens favorites.
- Standalone CLI for launching, inspection, CRUD and diagnostics.

## Why QOpen exists

Omarchy already launches installed desktop applications and shell commands well.
QOpen covers the layer that application indexes do not model cleanly:

- the project directory you open every day;
- a configuration file that belongs in a terminal editor;
- a carefully selected framework or library reference;
- a TUI with a memorable display name;
- a safe, explicit command invocation;
- an SSH destination grouped with the rest of an environment.

The catalog remains small, portable and understandable. QOpen never crawls your
home directory or silently adds resources.

## Relationship to Omarchy Menu

QOpen complements the stock Omarchy Menu; it does not replace it. The two
interfaces have deliberately different ownership:

| Concern | Omarchy Menu | QOpen |
| --- | --- | --- |
| Primary role | System control and application management | Curated personal resource access |
| Typical content | Apps, setup, install, remove, update, style and system actions | Projects, files, selected documentation, web tools, TUI commands and SSH targets |
| Data source | Omarchy defaults, application providers and menu extensions | `~/.config/qopen/config.json` |
| Organization | System-defined menus and routes | User-defined groups, descriptions and favorites |
| Best entry point | Stock shortcut or Omarchy bar button | `Super+Alt+O`, optional bar button or Omarchy Menu submenu |

The integration does not override stock identifiers. Omarchy Menu uses plugin
id `omarchy.menu` and layer namespace `omarchy-menu`; QOpen uses
`qopen.launcher` and `qopen-launcher`. Its menu-extension ids are namespaced as
`custom-qopen.*`. The recommended QOpen shortcut did not collide with the stock
menu binding on the tested Omarchy 4.0.1 setup, but local bindings should still
be checked before installation.

Keep system-wide operations such as application discovery, package installation,
updates, appearance and power actions in Omarchy Menu. Keep manually selected
projects, files, references and environment targets in QOpen. Mirroring all of
Apps, Install, Update or System inside QOpen would create unnecessary duplication.

The QOpen submenu inside Omarchy Menu is an optional bridge, and its bar widget
is also optional. Both menus are full-screen overlay surfaces with exclusive
keyboard focus. Launching QOpen from an Omarchy Menu action is safe because the
stock menu closes before running the action. QOpen also asks Omarchy Shell to
hide `omarchy.menu` whenever it opens, so invoking its separate shortcut while
the stock menu is visible does not leave two exclusive-focus overlays mounted.

## Requirements

- Omarchy with the current Omarchy Shell plugin commands.
- Quickshell as provided by Omarchy.
- Python 3.10 or newer.
- A Nerd Font for the supplied icons.
- `wl-clipboard` (`wl-paste` and `wl-copy`) for clipboard actions.

QOpen uses Omarchy launch helpers when available and checks the complete local
environment with:

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen --doctor
```

The 2.4.1 release was developed and verified on Omarchy 4.0.1, Quickshell
0.3.1 and Qt 6.11.2. These are tested versions, not strict pins.

## Installation

Install directly from GitHub:

```bash
omarchy plugin add https://github.com/CoderLambert/qopen-omarchy-plugin.git --enable
```

Review the repository before enabling it: Omarchy Shell plugins execute inside
the long-running shell process and are not sandboxed.

For a non-interactive install after review:

```bash
omarchy plugin add https://github.com/CoderLambert/qopen-omarchy-plugin.git --enable --yes
```

The plugin id is `qopen.launcher`. If you installed without `--enable`, enable
the optional bar widget later:

```bash
omarchy plugin enable qopen.launcher --section left
```

### Add QOpen to the Omarchy menu

Add the following entries to
`~/.config/omarchy/extensions/omarchy-menu.jsonc` inside the root object:

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

The Omarchy menu extension file hot-reloads after saving.

### Recommended keyboard shortcut

Add this binding to `~/.config/hypr/bindings.lua`:

```lua
o.bind(
  "SUPER + ALT + O",
  "QOpen resource search",
  "omarchy-shell shell toggle qopen.launcher '{}'"
)
```

Then validate Hyprland:

```bash
hyprctl reload
hyprctl configerrors
```

## Using the interface

Open QOpen from the shortcut, menu, bar widget or shell command:

```bash
omarchy-shell shell toggle qopen.launcher '{}'
```

Other useful routes:

```bash
# Favorites
omarchy-shell shell toggle qopen.launcher '{"favorites":true}'

# A specific collection
omarchy-shell shell toggle qopen.launcher '{"group":"projects"}'

# Open the add form
omarchy-shell shell toggle qopen.launcher '{"action":"add"}'

# Add a project and open its browser immediately
omarchy-shell shell toggle qopen.launcher \
  '{"action":"add","type":"project","browse":true}'

# Open the editor for a specific resource
omarchy-shell shell toggle qopen.launcher \
  '{"action":"edit","item":"react"}'
```

Route payloads only select the initial UI state. They do not bypass editor
validation or write the catalog directly.

### Usage preview

![QOpen grouped search showing React resources](docs/assets/qopen-usage.png)

The example shows a `react` search with curated collections on the left and
keyboard-friendly resource actions on the right. The screenshot is cropped to
the QOpen panel so it does not include the surrounding desktop.

### Search and collections

Type directly to search the selected collection. Collections are backed by the
resource `group` field, and QOpen displays their live item counts. Common groups
include `projects`, `frameworks`, `ui`, `testing`, `tools` and `docs`.

### Adding or editing resources

1. Press `Ctrl+N` or use `+ Add`.
2. Choose a resource type.
3. Fill in the name, id, group and type-specific target.
4. For file/project resources, paste a path or use the embedded browser.
5. Use Check to validate the target, then Save.

Resource type is fixed while editing so type-specific fields cannot be silently
lost. When a file or project is selected from the path browser, QOpen can infer
the name and id from the selected path; the values remain editable before save.

### Main interface keys

| Key | Action |
| --- | --- |
| Type or paste | Search the selected collection |
| Up / Down | Move the resource cursor |
| Enter | Open the selected resource |
| Escape | Clear search, close editor, then close QOpen |
| Ctrl+N | Add a resource |
| Ctrl+E | Edit the selected resource |
| Ctrl+D | Remove the selected resource after confirmation |
| Ctrl+R | Reload the catalog |
| Ctrl+Enter | Save while editing |

### Safe path browser keys

| Key | Action |
| --- | --- |
| Up / Down | Select an entry |
| Enter | Open a directory or choose a file |
| Alt+Up | Open the parent directory |
| Ctrl+L | Focus the path field |
| Ctrl+H | Toggle hidden entries |
| Escape | Return to the resource form |

Project mode lists directories only and chooses the current directory with the
footer button. File mode lists directories and regular files; double-clicking a
file chooses it immediately.

## Resource types

| Type | Required value | Launch behavior |
| --- | --- | --- |
| `web` | HTTP(S) target | Omarchy web app or the default browser |
| `project` | Directory path | Opens a terminal in that directory |
| `file` | File path | Opens the configured terminal editor |
| `tui` | Argument array | Opens through the Omarchy TUI helper |
| `command` | Argument array | Runs detached or in a terminal |
| `ssh` | Host or `user@host` | Opens `ssh` in a terminal |

Paths may use `~`, environment variables or absolute paths. Expansion occurs in
the Python backend, not through shell interpolation.

A useful catalog groups related resources together, for example React rich-text
editors, motion libraries, icon systems, TanStack tools, frameworks and testing
references. QOpen ships recommended ordering for its known frontend-oriented
groups while still allowing arbitrary group ids.

## Catalog format

The default catalog is stored at:

```text
~/.config/qopen/config.json
```

Example:

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

Important guarantees:

- ids contain lowercase letters, numbers, `_` or `-` and must be unique;
- each mutation validates the complete catalog;
- writes use a lock and same-directory atomic replacement;
- the previous catalog is retained as `config.json.bak`;
- new state files are private (`0600`), and existing permissions can be audited
  or repaired explicitly;
- QML never writes the catalog directly;
- personal resource data is not automatically synchronized to this GitHub repository.

Set `QOPEN_CONFIG` to use a different catalog with the CLI:

```bash
QOPEN_CONFIG=~/Documents/qopen-work.json \
  ~/.config/omarchy/plugins/qopen.launcher/bin/qopen --list
```

## Command-line interface

The backend is installed with the plugin:

```bash
QOPEN=~/.config/omarchy/plugins/qopen.launcher/bin/qopen

$QOPEN                         # Interactive resource picker
$QOPEN --groups                # Browse by collection
$QOPEN --favorites             # Browse favorites
$QOPEN --list                  # Print catalog items
$QOPEN <id>                    # Launch one item
$QOPEN add                     # Guided add flow
$QOPEN edit [id]               # Guided edit flow
$QOPEN remove [id]             # Confirmed removal
$QOPEN favorite <id> toggle    # Toggle favorite state
$QOPEN recover                 # Validate and restore config.json.bak
$QOPEN fix-permissions         # Restrict QOpen state files to mode 0600
$QOPEN --edit                  # Open raw JSON in the configured editor
$QOPEN --doctor                # Validate dependencies and every item
$QOPEN --version
```

Non-interactive example:

```bash
$QOPEN add project \
  --id qopen \
  --name "QOpen Plugin" \
  --group projects \
  --target ~/Code/qopen-omarchy-plugin \
  --favorite
```

The `api` subcommands are a machine interface used by QML. They emit compact
JSON and should not be treated as a long-term public integration API yet.

## Architecture and safety

```text
Omarchy menu / shortcut / bar widget
                 |
                 v
             QOpen.qml
                 |
       +---------+----------+
       |                    |
ResourceEditor.qml     PathPicker.qml
       |                    |
       +---------+----------+
                 | argv only
                 v
              bin/qopen
                 |
       config lock + validation
                 |
                 v
       ~/.config/qopen/config.json
```

QML owns presentation, focus and interaction. Python owns directory listing,
normalization, validation, persistence and process dispatch.

The embedded path browser deliberately avoids Qt `FileDialog`, GTK, GIO and
GVFS. QOpen runs inside the shared Omarchy Shell process; keeping native file
dialog integration out of that process prevents a picker failure from
terminating the entire desktop shell. Version 2.2 briefly used native dialogs;
2.3 removed them after reproducible Quickshell crashes. The evidence and release
validation are documented in [DEVELOPMENT.md](DEVELOPMENT.md).

Commands are passed as argument arrays. Resource values are never concatenated
into a shell command by QML.

## Updating and removing

Update a Git-installed copy:

```bash
omarchy plugin update qopen.launcher --yes
```

Remove the plugin:

```bash
omarchy plugin remove qopen.launcher --yes
```

Removal does not delete `~/.config/qopen/config.json`, so the personal catalog
can be re-used after reinstalling.

## Troubleshooting

### QOpen does not appear

```bash
omarchy plugin validate ~/.config/omarchy/plugins/qopen.launcher
omarchy-shell shell rescanPlugins
omarchy restart shell
```

### A resource will not open

Run the doctor and inspect the failed item:

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen --doctor
```

For files and projects, confirm that the expanded path exists. For TUI and
command resources, confirm that the first executable is available on `PATH`.

### The catalog is invalid

QOpen refuses partial or malformed writes. Inspect:

```text
~/.config/qopen/config.json
~/.config/qopen/config.json.bak
```

The backup is the catalog state immediately before the last successful
mutation. Restore it only after validation:

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen recover
```

Before replacing the catalog, QOpen preserves the current invalid file as a
private timestamped `config.json.invalid-*` snapshot. If `--doctor` reports
group- or world-readable state files, repair them explicitly:

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen fix-permissions
```

### Development reload issues

Omarchy normally hot-reloads files below `~/.config/omarchy/plugins`. For a
multi-file change, restart the shared shell once after copying all files:

```bash
omarchy restart shell
```

This avoids repeatedly rebuilding the plugin graph while files are in a
transitional state.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture decisions, release
history, the 2.3 native file-dialog incident, validation procedures and the
maintainer workflow. User-facing changes are recorded in
[CHANGELOG.md](CHANGELOG.md).

Run the portable backend test suite with:

```bash
python -m unittest discover -s tests -v
```

## License

[MIT](LICENSE) © 2026 CoderLambert
